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

| Provider     | Hostname                |
|--------------|-------------------------|
| OpenAI       | `api.openai.com`        |
| Anthropic    | `api.anthropic.com`     |
| OpenRouter   | `openrouter.ai`         |
| Nous         | `api.nous.ai`           |

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

### 4. Inject the proxy configuration into the tenant `.env`
Append these lines to `/opt/aaas/tenants/{tenant-id}/.env`:

```bash
cat >> /opt/aaas/tenants/{tenant-id}/.env <<EOF

# Agent Vault proxy — injected by admin agent during onboarding
HTTP_PROXY=http://agent-vault:14322
HTTPS_PROXY=http://agent-vault:14322
AGENT_VAULT_ADDR=http://agent-vault:14321
AGENT_VAULT_TOKEN=${VAULT_TOKEN}
AGENT_VAULT_VAULT={tenant-id}-vault
EOF
```

After writing, verify the file does NOT contain the real LLM API key:
```bash
grep -i "sk-\|key=" /opt/aaas/tenants/{tenant-id}/.env | grep -v "AGENT_VAULT_TOKEN"
# Expected: no output (any real API key lines should be absent)
```

### 5. Set a placeholder for the LLM API key env var
The tenant container expects the provider API key env var (e.g. `OPENAI_API_KEY`)
to exist in the environment so the LLM client library initialises correctly.
Set it to a placeholder value that can never be mistaken for a real key:

```bash
sed -i 's|^OPENAI_API_KEY=.*|OPENAI_API_KEY=routed-via-agent-vault|' \
  /opt/aaas/tenants/{tenant-id}/.env
```

Replace `OPENAI_API_KEY` with the provider-specific env var name.
The proxy will intercept calls to the provider hostname and inject the real key
from the vault before the request leaves the host.

### 6. Attach the tenant service to agent-vault-net
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
    external: true
```

Using `external: true` tells Compose that this network was created by the
agent-vault service's own Compose file and should not be recreated.

### 7. Confirm
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