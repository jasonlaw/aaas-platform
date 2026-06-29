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

### 1a. Create the tenant's isolated bridge network
Each tenant gets its own isolated Docker bridge network, distinct from the
shared `agent-vault-net`. This prevents lateral movement between tenant
containers — a compromised tenant can no longer probe any other tenant's
container on a shared network.

```bash
docker network create hermes-{tenant-id}-net
```

If the network already exists (re-onboarding or recovery), skip creation.

### 1b. Connect Agent Vault to this tenant's network
Agent Vault joins every tenant's isolated network so it can still serve the
proxy port (`:14322`) to that tenant. The Agent Vault container stays
running — no restart needed.

```bash
docker network connect hermes-{tenant-id}-net agent-vault
```

If Agent Vault is already connected to this network (re-onboarding or
recovery), this command will fail harmlessly with "endpoint already
exists" — safe to ignore.

### 2. Store the credential and register the LLM provider service
Identify the provider hostname from the tenant's LLM provider:

| Provider         | Hostname                |
|------------------|-------------------------|
| OpenAI           | `api.openai.com`        |
| Anthropic        | `api.anthropic.com`     |
| OpenRouter       | `openrouter.ai`         |
| Nous             | `api.nous.ai`           |
| OpenCode Zen     | `opencode.ai`           |

Store the credential (replace `{tenant-id}`, `{provider-env-var}` — the exact
var name collected in onboard-tenant step 1 — and `{real-api-key}`):
```bash
agent-vault vault credential set {provider-env-var}={real-api-key} --vault {tenant-id}-vault
```

Then register the service mapping: which hostname this credential is allowed
to be injected into, and how:
```bash
agent-vault vault service add \
  --vault {tenant-id}-vault \
  --name {provider-env-var} \
  --host {hostname} \
  --auth-type Bearer \
  --token-key {provider-env-var}
```

The key is stored encrypted in Agent Vault. It must not be written to `.env`
or any other file after this point. Only hosts with a registered service are
reachable through the proxy — see step 7 (no separate policy command needed
in this CLI version; this is what scopes egress).

### 3. Create an agent token for this tenant
```bash
VAULT_TOKEN=$(agent-vault agent create --vault {tenant-id}-vault:proxy --name hermes_{tenant-id} --token-only)
```

The `:proxy` suffix on `--vault` scopes the token to proxy access only — it
grants the tenant container proxy access to `{tenant-id}-vault` only and
cannot read the raw credential value, only route requests through the proxy.
`--token-only` prints just the token (replaces the older `--print-token` flag).

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
# The token is embedded as the Basic auth username in the proxy URL so that
# httpx/openai SDK sends a Proxy-Authorization header on every CONNECT request.
# Agent Vault's MITM proxy (port 14322) requires this — unauthenticated CONNECT
# requests are rejected with 407.
HTTP_PROXY=http://${VAULT_TOKEN}@agent-vault:14322
HTTPS_PROXY=http://${VAULT_TOKEN}@agent-vault:14322
NO_PROXY=api.telegram.org,localhost,127.0.0.1
AGENT_VAULT_TOKEN=${VAULT_TOKEN}
AGENT_VAULT_VAULT={tenant-id}-vault
# Python's SSL context (used by httpx/openai SDK) defaults to the certifi bundle,
# which does not include Agent Vault's self-signed MITM CA. Pointing SSL_CERT_FILE
# to the system CA bundle causes Python to trust the CA that was installed into
# the image by the Dockerfile's update-ca-certificates step.
SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
EOF
```

**`AGENT_VAULT_ADDR` is intentionally not injected here.** Tenant containers
have no legitimate reason to call Agent Vault's management API (`:14321`) —
only the proxy port (`:14322`, reached implicitly via `HTTP_PROXY`/
`HTTPS_PROXY`) is needed. Each tenant's isolated network (step 1a/1b) means
the management port is unreachable from inside the tenant container anyway,
but omitting the env var removes even the path of least resistance.

If the tenant's harness or skills call other external APIs beyond the LLM
provider and Telegram, add their hostnames to `NO_PROXY` too, unless you have
also registered a service for them in step 2 — anything not registered and
not in `NO_PROXY` is rejected by the proxy by default (see step 7), it does
not transit unmanaged.

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

### 7. Confirm the vault's egress scope
Unlike earlier Agent Vault versions, CLI v0.39.0 has no separate
`vault update --unmatched-host-policy` command — there is no policy to set.
A vault denies any host that does not have a registered service by default.
Step 2 already scoped this vault to exactly one reachable host (the LLM
provider hostname registered there); nothing further is required here. If the
tenant's harness or skills call other external APIs, either register an
additional service for that host (step 2's pattern) or route it outside the
proxy via `NO_PROXY` (step 5) — anything neither registered nor excluded is
rejected by the proxy, not passed through.

### 8. Attach the tenant service to its isolated network
When the onboard-tenant SOP writes the service block in `docker-compose.yaml`,
it must include this tenant's isolated network (created in step 1a, with
Agent Vault already joined to it in step 1b) — **not** the shared
`agent-vault-net`:

```yaml
  hermes_{tenant-id}:
    ...
    networks:
      - hermes-{tenant-id}-net
```

Declare the network block at the bottom of docker-compose.yaml if not already
present:
```yaml
networks:
  hermes-{tenant-id}-net:
    name: hermes-{tenant-id}-net
    external: true
```

Using `external: true` tells Compose that this network was created outside
this Compose file (by step 1a's `docker network create`) and should not be
recreated. The explicit `name:` is required for the same reason it was
required for `agent-vault-net` in earlier platform versions — without it,
Compose would project-prefix the network name and `docker compose up` would
fail with "network not found".

Each tenant's network has exactly two members: that tenant's container and
Agent Vault. A compromised tenant container can no longer reach any other
tenant's container, since they no longer share a network. Agent Vault's
management port (`:14321`) is bound to `127.0.0.1` on the host only (see
`/opt/aaas/agent-vault/docker-compose.yaml`), so it is unreachable from any
container regardless of which Docker network that container is on.

### 9. Confirm
```bash
# Verify vault exists with correct credential and service
agent-vault vault credential list --vault {tenant-id}-vault
agent-vault vault service list --vault {tenant-id}-vault
# Expected: one credential and one service entry for the provider hostname

# Verify token
agent-vault agent list --vault {tenant-id}-vault
# Expected: hermes_{tenant-id} agent listed

# Verify the tenant's isolated network exists and Agent Vault has joined it
docker network inspect hermes-{tenant-id}-net --format '{{range .Containers}}{{.Name}} {{end}}'
# Expected: agent-vault listed (the tenant container itself joins when its
# compose service starts in onboard-tenant step 9 / update-tenant step 10)
```

Return control to the calling SOP (onboard-tenant step 9 or update-tenant step 10).

## Notes
- Never store the real API key in `.env`, `config.yaml`, or any file in the tenant volume.
- Each tenant has its own isolated Docker network (`hermes-{tenant-id}-net`),
  created in step 1a, with only that tenant's container and Agent Vault as
  members. Tenants never share a network with each other.
- The `AGENT_VAULT_TOKEN` in `.env` is a scoped proxy token, not a credential — it
  grants no direct access to the stored key. Tokens minted by `agent-vault agent create`
  are prefixed `av_agt_`; that prefix identifies a proxy token, not a credential
  key, so it is safe to keep in `.env` and should not be mistaken for a leaked secret.
- Tenant `.env` files sometimes accumulate provider key variables left over from a
  prior choice of LLM provider, even though only one provider is active per
  `config.yaml`. Step 4 only scrubs the currently active `{provider-env-var}`; if
  the `.env` file holds stale keys under a different provider's variable name,
  remove those lines (or store and scrub them the same way) rather than leaving a
  live, unscrubbed key sitting in the file unused.
- To change a tenant's LLM API key, re-run the full onboard-tenant flow for that
  tenant (offboard and re-onboard), or contact the platform operator to update
  the credential directly in Agent Vault via `agent-vault vault credential update`.
- If Agent Vault is down, tenant containers will fail all LLM calls. See
  `/opt/aaas/platform/incidents/agent-vault-failure.md` for recovery.