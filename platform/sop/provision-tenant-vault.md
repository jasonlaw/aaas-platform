# SOP: Provision Tenant Vault

## Purpose
Register a scoped vault and credential entry in Agent Vault for one tenant,
then inject the proxy token into the tenant's `.env`. Called as a sub-step
of the onboard-tenant SOP (after `.env` is created, before container start).

This SOP must not be run in isolation — it is always called from onboard-tenant
or update-tenant when credentials change.

## Pre-requisites
- Agent Vault container is running and healthy:
  `/opt/aaas/platform/scripts/agent-vault-health.sh`
- `agent-vault` CLI is installed and authenticated on the host:
  `agent-vault vault list` must succeed without error
- Tenant `.env` exists at `/opt/aaas/tenants/{tenant-id}/.env`

## Steps

### 1. Create the tenant vault
Vault name follows the `{tenant-id}-vault` convention:
```bash
agent-vault vault create {tenant-id}-vault
```

If the vault already exists (re-onboarding or recovery), skip creation and
proceed to step 2.

### 2. Register the LLM provider service
Identify the provider hostname from the tenant's LLM provider:

| Provider         | Hostname                |
|------------------|-------------------------|
| OpenAI           | `api.openai.com`        |
| Anthropic        | `api.anthropic.com`     |
| OpenRouter       | `openrouter.ai`         |
| Nous             | `api.nous.ai`           |
| OpenCode Zen     | `opencode.ai`           |

Register the credential (replace `{hostname}` and `{real-api-key}`):
```bash
agent-vault vault credential add {tenant-id}-vault \
  --host {hostname} \
  --auth-type Bearer \
  --secret {real-api-key}
```

The key is stored encrypted in Agent Vault. It must not be written to `.env`
or any other file after this point.

### 3. Create an agent token for this tenant
```bash
VAULT_TOKEN=$(agent-vault vault agent create {tenant-id}-vault --name hermes_{tenant-id} --print-token)
```

This token grants the tenant container proxy access to `{tenant-id}-vault` only.
It cannot read the raw credential value — it can only route requests through the proxy.

### 4. Set a placeholder for the LLM API key env var — BEFORE injecting proxy config
The tenant `.env` was rendered in onboard-tenant step 5 with the real key under the
provider-specific env var name collected in onboard-tenant step 1 (e.g.
`ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `NOUS_API_KEY`, `OPENAI_API_KEY`,
`OPENCODE_API_KEY`).
Use that exact variable name here — **do not hardcode `OPENAI_API_KEY`**, or the
real key will never be scrubbed for any other provider:

```bash
PROVIDER_VAR={provider-env-var}   # the exact var name collected in onboard-tenant step 1
sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" \
  /opt/aaas/tenants/{tenant-id}/.env
```

The tenant container still needs this env var to exist (so the LLM client library
initialises without error) — it just no longer holds a real value. The proxy
intercepts calls to the provider hostname and injects the real key from the vault
before the request leaves the host.

### 5. Inject the proxy configuration into the tenant `.env`
Append these lines to `/opt/aaas/tenants/{tenant-id}/.env`:

```bash
cat >> /opt/aaas/tenants/{tenant-id}/.env <<EOF

# Agent Vault proxy — injected by admin agent during onboarding
# Only the LLM provider host above is routed through the proxy; NO_PROXY keeps
# everything else (Telegram, future integrations) on a direct connection so
# Agent Vault never sees traffic it wasn't scoped to handle.
HTTP_PROXY=http://agent-vault:14322
HTTPS_PROXY=http://agent-vault:14322
NO_PROXY=api.telegram.org,localhost,127.0.0.1
AGENT_VAULT_ADDR=http://agent-vault:14321
AGENT_VAULT_TOKEN=${VAULT_TOKEN}
AGENT_VAULT_VAULT={tenant-id}-vault
EOF
```

If the tenant's harness or skills call other external APIs beyond the LLM
provider and Telegram, add their hostnames to `NO_PROXY` too, unless you have
also registered a credential for them in step 2 — anything not registered and
not in `NO_PROXY` either fails (if the vault is in strict deny mode, see the
note below) or transits the MITM proxy unmanaged.

### 6. Verify the real key is gone
Two checks — both must pass before continuing:

```bash
# 1. The provider var must hold the placeholder, not a real value
grep -qx "${PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/tenants/{tenant-id}/.env \
  && echo "OK: placeholder set" \
  || echo "FAIL: ${PROVIDER_VAR} does not hold the placeholder — step 4 did not run or targeted the wrong var name"

# 2. No line in the file still contains something that looks like a live key
#    (common provider key prefixes). Do NOT just grep for "key=" — every line
#    that sets *_API_KEY contains that substring whether or not it's scrubbed,
#    so that pattern alone can never report "no output" and is not a real check.
grep -E "(sk-[A-Za-z0-9_-]{10,}|sk-ant-|sk-or-v1-)" /opt/aaas/tenants/{tenant-id}/.env
# Expected: no output. Any match here is a real key that step 4 failed to scrub.
```

### 7. Set the vault's egress policy (deny unmatched hosts)
By default Agent Vault forwards requests to hosts that don't match a registered
service as plain passthrough traffic instead of blocking them. Since the proxy
is also the tenant's only route to the wider internet, leaving this on the
default lets a compromised or misbehaving tenant agent reach arbitrary hosts
through it. Set the vault to reject anything unregistered instead:

```bash
agent-vault vault update {tenant-id}-vault --unmatched-host-policy deny
```

(Flag name per the installed `agent-vault` CLI version — confirm with
`agent-vault vault update --help` if this errors; the setting itself is
documented upstream as `unmatched_host_policy`.) Combined with the `NO_PROXY`
entries in step 5, this means: known non-LLM hosts (Telegram) bypass the proxy
entirely, and anything neither registered nor excluded is rejected rather than
silently passed through.

### 8. Attach the tenant service to agent-vault-net
When the onboard-tenant SOP writes the service block in `docker-compose.yaml`,
it must include the `agent-vault-net` network:

```yaml
  hermes_{tenant-id}:
    ...
    networks:
      - agent-vault-net
```

If the network block is not already declared at the bottom of docker-compose.yaml,
add it:
```yaml
networks:
  agent-vault-net:
    name: agent-vault-net
    external: true
```

Using `external: true` tells Compose that this network was created by the
agent-vault service's own Compose file and should not be recreated. The
explicit `name: agent-vault-net` is required — without it Compose resolves the
network name to `agent-vault-net` literally on this side but the producing
Compose file (`/opt/aaas/agent-vault/docker-compose.yaml`) would otherwise
create it as `agent-vault_agent-vault-net` (project-prefixed), and `docker
compose up` for this service would fail with "network not found". Both
Compose files must pin the literal name `agent-vault-net`.

### 9. Confirm
```bash
# Verify vault exists with correct credential
agent-vault vault credential list {tenant-id}-vault
# Expected: one entry for the provider hostname

# Verify token
agent-vault vault agent list {tenant-id}-vault
# Expected: hermes_{tenant-id} agent listed
```

Return control to the calling SOP (onboard-tenant step 9 or update-tenant step 10).

## Rotating credentials later
To replace a tenant's LLM API key without interrupting the container:
1. `agent-vault vault credential update {tenant-id}-vault --host {hostname} --secret {new-key}`
2. No container restart required — the vault injects the new key on the next proxied request.

## Notes
- Never store the real API key in `.env`, `config.yaml`, or any file in the tenant volume.
- The `AGENT_VAULT_TOKEN` in `.env` is a scoped proxy token, not a credential — it
  grants no direct access to the stored key.
- If Agent Vault is down, tenant containers will fail all LLM calls. See
  `/opt/aaas/platform/incidents/agent-vault-failure.md` for recovery.