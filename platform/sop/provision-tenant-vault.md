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

### 1b. Start a forwarding-only sidecar on this tenant's network
Agent Vault itself must never join a tenant network — it listens on both the
proxy port (`:14322`) and the management API (`:14321`) on the same
interface, so joining a tenant network directly would make the management
API reachable from inside that tenant's container too (confirmed by the
`agent_vault_mgmt_port_not_reachable_from_tenant` harness check). Instead,
start a minimal TCP-forwarding sidecar that joins both `agent-vault-net` and
this tenant's network, and only ever forwards the proxy port:

```bash
docker run -d \
  --name agent-vault-proxy-{tenant-id} \
  --restart unless-stopped \
  --network agent-vault-net \
  alpine/socat \
  TCP-LISTEN:14322,fork,reuseaddr TCP:agent-vault:14322

docker network connect hermes-{tenant-id}-net agent-vault-proxy-{tenant-id}
```

If re-onboarding or recovering a tenant provisioned before this fix, Agent
Vault may still be directly connected to this network from the old
connect-Agent-Vault-itself design. Drop that connection now that the
sidecar covers it — leaving it in place defeats the isolation fix even
though the sidecar is also present:

```bash
docker network disconnect hermes-{tenant-id}-net agent-vault 2>/dev/null || true
```

If the sidecar container already exists (re-onboarding or recovery), skip
creation and only run the `docker network connect` line; it fails harmlessly
with "endpoint already exists" if already connected — safe to ignore.

The sidecar has no route to `:14321` to forward in the first place, so even
full compromise of the sidecar process does not expose the management API —
this is a structural property of what the container can reach, not an
access-control rule that could be misconfigured.

### 2. Store the credential and register the LLM provider service
Identify the provider hostname from the tenant's LLM provider. Full catalog,
derivation rule for the env var, and exceptions (OAuth-only / multi-credential
providers to escalate rather than auto-configure):
`/opt/aaas/platform/reference/llm-provider-catalog.md`. Most commonly used at
the time of writing:

| Provider ID      | Hostname                |
|-------------------|--------------------------|
| `openai`         | `api.openai.com`        |
| `anthropic`      | `api.anthropic.com`     |
| `openrouter`     | `openrouter.ai`         |
| `nous`           | `api.nous.ai`           |
| `opencode-zen`   | `opencode.ai`           |
| `opencode-go`    | `opencode.ai`           |

Store the credential (replace `{tenant-id}`, `{provider-env-var}` — derived
from the Provider ID via the catalog's rule, never asked of the operator —
and `{real-api-key}`):
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

### 2.1. (Optional) Store the fallback provider credential and register its service
Skip this section entirely if onboard-tenant step 1 did not collect a
fallback provider. If it did, `fallback_providers:` in `config.yaml` (step 5
of onboard-tenant) already names the fallback provider:model — the proxy
still needs its own registered service before Hermes can actually reach that
host, exactly like the primary provider above. Use the same hostname table
and the fallback provider's own env var and key (replace `{fallback-provider-env-var}`
and `{fallback-real-api-key}`; both are distinct from the primary's):

```bash
agent-vault vault credential set {fallback-provider-env-var}={fallback-real-api-key} --vault {tenant-id}-vault

agent-vault vault service add \
  --vault {tenant-id}-vault \
  --name {fallback-provider-env-var} \
  --host {fallback-hostname} \
  --auth-type Bearer \
  --token-key {fallback-provider-env-var}
```

Both credentials live in the same `{tenant-id}-vault` — one vault per tenant,
not one per provider. If the fallback provider is the same provider as
primary (different model, same host), this step still runs; it is harmless
to register the same host twice under different env var names, and most
fallback configurations use a different provider/host than the primary by
design (the whole point is resilience if the primary host is unreachable).

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
provider-specific env var name derived from the catalog in onboard-tenant step 1
(e.g. `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `NOUS_API_KEY`, `OPENAI_API_KEY`,
`OPENCODE_ZEN_API_KEY`, `OPENCODE_GO_API_KEY`).
Use that exact variable name here — **do not hardcode `OPENAI_API_KEY`**, or the
real key will never be scrubbed for any other provider:

```bash
PROVIDER_VAR={provider-env-var}   # derived from the catalog in onboard-tenant step 1
sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" \
  /opt/aaas/tenants/{tenant-id}/.env
```

The tenant container still needs this env var to exist (so the LLM client library
initialises without error) — it just no longer holds a real value. The proxy
intercepts calls to the provider hostname and injects the real key from the vault
before the request leaves the host.

### 4.1. (Optional) Set a placeholder for the fallback provider's LLM API key env var
Skip if no fallback provider was collected. Otherwise, same pattern as step 4,
under the fallback's own env var name — `.env` must hold the placeholder for
both the primary and fallback provider vars, never a real key for either:

```bash
FALLBACK_PROVIDER_VAR={fallback-provider-env-var}
sed -i "s|^${FALLBACK_PROVIDER_VAR}=.*|${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault|" \
  /opt/aaas/tenants/{tenant-id}/.env
```

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
HTTP_PROXY=http://${VAULT_TOKEN}@agent-vault-proxy-{tenant-id}:14322
HTTPS_PROXY=http://${VAULT_TOKEN}@agent-vault-proxy-{tenant-id}:14322
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
# Expected: no output. Any match here is a real key that step 4 (or 4.1) failed to scrub.

# 3. (Optional) If a fallback provider was collected, the fallback var must also
#    hold the placeholder — check separately, it is a different var name than step 1's.
grep -qx "${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/tenants/{tenant-id}/.env \
  && echo "OK: fallback placeholder set" \
  || echo "FAIL: ${FALLBACK_PROVIDER_VAR} does not hold the placeholder — step 4.1 did not run or targeted the wrong var name"
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
# Expected: agent-vault-proxy-{tenant-id} listed (the forwarding sidecar joins
# the tenant network here; Agent Vault itself never joins a tenant network directly.
# The tenant container itself joins when its compose service starts in
# onboard-tenant step 9 / update-tenant step 10)
```

Return control to the calling SOP (onboard-tenant step 9 or update-tenant step 10).

## Notes
- Never store the real API key in `.env`, `config.yaml`, or any file in the tenant volume.
- If onboard-tenant collected a fallback provider (optional), steps 2.1, 4.1, and
  the step 6 check above register and scrub it the same way as the primary
  provider. Skip all three if no fallback provider was collected — this is the
  common case and is not an error. See
  https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers
  for what `fallback_providers:` in `config.yaml` actually does at runtime.
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