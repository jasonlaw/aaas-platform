#!/usr/bin/env bash
# Provision Agent Vault for one tenant: create the vault, isolated network,
# forwarding sidecar, credential, proxy token, and inject proxy config into .env.
#
# Replaces provision-tenant-vault.md as the execution path for onboard-tenant.md
# step 6.3. The SOP document is retained as reference documentation but is no
# longer in the agent's execution path.
#
# This script runs all deterministic steps from provision-tenant-vault.md:
#   step 1    — create the tenant vault
#   step 1a   — create the isolated bridge network
#   step 1b   — start forwarding sidecar and connect to tenant network
#   step 2    — store primary credential and register LLM provider service
#   step 2.1  — (optional) store fallback credential and register its service
#   step 3    — create agent proxy token
#   step 4    — replace real primary key in .env with placeholder
#   step 4.1  — (optional) replace fallback key placeholder
#   step 5    — inject HTTP_PROXY / HTTPS_PROXY / AGENT_VAULT_TOKEN / etc. into .env
#   step 6    — verify no real key remains in .env
#   step 7    — confirm egress scope (no command needed in CLI v0.39.0+)
#   step 9    — print confirmation of vault, network, and token state
#
# step 8 (network declaration in docker-compose.yaml) is handled by
# add-tenant-compose-service.sh, which already writes the correct network block.
#
# Usage:
#   provision-tenant-vault.sh {tenant-id} {provider-env-var} {real-api-key} \
#     [{fallback-provider-env-var} {fallback-real-api-key}]
#
#   {provider-env-var}   — exact var name from onboard-tenant step 1, e.g. ANTHROPIC_API_KEY
#   {real-api-key}       — the actual key value (never written to disk after this script runs)
#   fallback-* args      — optional; omit entirely if no fallback provider was collected
#
# Environment overrides (for testing):
#   TENANT_ROOT   (default: /opt/aaas/tenants)

set -euo pipefail

TENANT_ID="${1:-}"
PROVIDER_VAR="${2:-}"
REAL_API_KEY="${3:-}"
FALLBACK_PROVIDER_VAR="${4:-}"
FALLBACK_REAL_API_KEY="${5:-}"

TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"

usage() {
  cat >&2 <<'EOF'
Usage: provision-tenant-vault.sh {tenant-id} {provider-env-var} {real-api-key} \
         [{fallback-provider-env-var} {fallback-real-api-key}]

Examples:
  # Primary provider only:
  provision-tenant-vault.sh acme-coffee ANTHROPIC_API_KEY sk-ant-xxxxx

  # Primary + fallback:
  provision-tenant-vault.sh acme-coffee ANTHROPIC_API_KEY sk-ant-xxxxx \
    OPENROUTER_API_KEY sk-or-v1-xxxxx
EOF
}

fail() {
  echo "FAIL  $1" >&2
  exit 1
}

pass() {
  echo "PASS  $1"
}

# Provider hostname lookup
provider_host() {
  local var_name="$1"
  case "$var_name" in
    OPENAI_API_KEY)       echo "api.openai.com" ;;
    ANTHROPIC_API_KEY)    echo "api.anthropic.com" ;;
    OPENROUTER_API_KEY)   echo "openrouter.ai" ;;
    NOUS_API_KEY)         echo "api.nous.ai" ;;
    OPENCODE_API_KEY)     echo "opencode.ai" ;;
    *)
      echo "WARN  unknown provider env var '$var_name' — could not auto-detect hostname" >&2
      echo ""
      return 1
      ;;
  esac
}

# --- Argument validation ---

if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  usage
  fail "missing or invalid tenant-id"
fi

if [ -z "$PROVIDER_VAR" ]; then
  usage
  fail "missing provider-env-var (e.g. ANTHROPIC_API_KEY)"
fi

if [ -z "$REAL_API_KEY" ]; then
  usage
  fail "missing real-api-key"
fi

# If one fallback arg is given, both are required
if [ -n "$FALLBACK_PROVIDER_VAR" ] && [ -z "$FALLBACK_REAL_API_KEY" ]; then
  usage
  fail "fallback-provider-env-var given but fallback-real-api-key is missing"
fi

TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
ENV_FILE="$TENANT_DIR/.env"

[ -d "$TENANT_DIR" ] \
  || fail "tenant directory not found: $TENANT_DIR — run onboard-tenant steps 1–5 first"

[ -f "$ENV_FILE" ] \
  || fail "tenant .env not found at $ENV_FILE — render tenant files before provisioning"

# --- Pre-requisite check ---
agent-vault vault list >/dev/null 2>&1 \
  || fail "agent-vault CLI not authenticated — run 'agent-vault vault list' to verify"

# --- Step 1: Create the tenant vault ---

VAULT_NAME="${TENANT_ID}-vault"

if agent-vault vault list 2>/dev/null | grep -q "^${VAULT_NAME}$"; then
  echo "SKIP  vault ${VAULT_NAME} already exists"
else
  agent-vault vault create "${VAULT_NAME}"
  pass "vault ${VAULT_NAME} created"
fi

# --- Step 1a: Create the isolated bridge network ---

NETWORK_NAME="hermes-${TENANT_ID}-net"

if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "SKIP  network ${NETWORK_NAME} already exists"
else
  docker network create "${NETWORK_NAME}"
  pass "network ${NETWORK_NAME} created"
fi

# --- Step 1b: Forwarding sidecar ---

SIDECAR_NAME="agent-vault-proxy-${TENANT_ID}"

if docker ps -a --format '{{.Names}}' | grep -qx "${SIDECAR_NAME}"; then
  echo "SKIP  sidecar ${SIDECAR_NAME} already exists"
else
  docker run -d \
    --name "${SIDECAR_NAME}" \
    --restart unless-stopped \
    --network agent-vault-net \
    alpine/socat \
    TCP-LISTEN:14322,fork,reuseaddr TCP:agent-vault:14322
  pass "sidecar ${SIDECAR_NAME} started on agent-vault-net"
fi

docker network connect "${NETWORK_NAME}" "${SIDECAR_NAME}" 2>/dev/null || true
pass "sidecar ${SIDECAR_NAME} connected to ${NETWORK_NAME}"

# Drop any direct Agent Vault connection that predates this isolation fix
docker network disconnect "${NETWORK_NAME}" agent-vault 2>/dev/null || true

# --- Step 2: Store primary credential and register service ---

PRIMARY_HOST="$(provider_host "$PROVIDER_VAR")" \
  || fail "cannot map $PROVIDER_VAR to a provider hostname — add it to the provider_host() table in this script"

agent-vault vault credential set "${PROVIDER_VAR}=${REAL_API_KEY}" --vault "${VAULT_NAME}"
pass "primary credential ${PROVIDER_VAR} stored in ${VAULT_NAME}"

agent-vault vault service add \
  --vault "${VAULT_NAME}" \
  --name "${PROVIDER_VAR}" \
  --host "${PRIMARY_HOST}" \
  --auth-type Bearer \
  --token-key "${PROVIDER_VAR}"
pass "primary service registered: ${PROVIDER_VAR} → ${PRIMARY_HOST}"

# --- Step 2.1: (Optional) Fallback provider ---

if [ -n "$FALLBACK_PROVIDER_VAR" ]; then
  FALLBACK_HOST="$(provider_host "$FALLBACK_PROVIDER_VAR")" \
    || fail "cannot map $FALLBACK_PROVIDER_VAR to a provider hostname — add it to the provider_host() table in this script"

  agent-vault vault credential set "${FALLBACK_PROVIDER_VAR}=${FALLBACK_REAL_API_KEY}" --vault "${VAULT_NAME}"
  pass "fallback credential ${FALLBACK_PROVIDER_VAR} stored in ${VAULT_NAME}"

  agent-vault vault service add \
    --vault "${VAULT_NAME}" \
    --name "${FALLBACK_PROVIDER_VAR}" \
    --host "${FALLBACK_HOST}" \
    --auth-type Bearer \
    --token-key "${FALLBACK_PROVIDER_VAR}"
  pass "fallback service registered: ${FALLBACK_PROVIDER_VAR} → ${FALLBACK_HOST}"
fi

# --- Step 3: Create agent proxy token ---

VAULT_TOKEN="$(agent-vault agent create --vault "${VAULT_NAME}:proxy" --name "hermes_${TENANT_ID}" --token-only)"
pass "agent proxy token created for hermes_${TENANT_ID}"

# --- Step 4: Scrub primary key from .env ---

sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" "$ENV_FILE"
pass "${PROVIDER_VAR} scrubbed from .env (replaced with placeholder)"

# --- Step 4.1: (Optional) Scrub fallback key from .env ---

if [ -n "$FALLBACK_PROVIDER_VAR" ]; then
  sed -i "s|^${FALLBACK_PROVIDER_VAR}=.*|${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault|" "$ENV_FILE"
  pass "${FALLBACK_PROVIDER_VAR} scrubbed from .env (replaced with placeholder)"
fi

# --- Step 5: Inject proxy config ---

cat >> "$ENV_FILE" <<EOF

# Agent Vault proxy — injected by provision-tenant-vault.sh during onboarding
# Only the registered LLM provider host(s) are routed through the proxy; NO_PROXY
# keeps everything else (Telegram, future integrations) on a direct connection.
# The token is embedded as the Basic auth username so httpx/openai SDK sends a
# Proxy-Authorization header on every CONNECT request (port 14322 requires this).
HTTP_PROXY=http://${VAULT_TOKEN}@${SIDECAR_NAME}:14322
HTTPS_PROXY=http://${VAULT_TOKEN}@${SIDECAR_NAME}:14322
NO_PROXY=api.telegram.org,localhost,127.0.0.1
AGENT_VAULT_TOKEN=${VAULT_TOKEN}
AGENT_VAULT_VAULT=${VAULT_NAME}
# Python's SSL context defaults to certifi, which does not include Agent Vault's
# self-signed MITM CA. Point to the system bundle (installed by the Dockerfile's
# update-ca-certificates step) so it is trusted.
SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
EOF

pass "proxy config injected into .env"

# --- Step 6: Verify no real key remains ---

ERRORS=0

if grep -qx "${PROVIDER_VAR}=routed-via-agent-vault" "$ENV_FILE"; then
  pass "primary placeholder confirmed in .env"
else
  echo "FAIL  ${PROVIDER_VAR} placeholder not found in .env — step 4 may have failed" >&2
  ERRORS=$((ERRORS + 1))
fi

if grep -E "(sk-[A-Za-z0-9_-]{10,}|sk-ant-|sk-or-v1-)" "$ENV_FILE"; then
  echo "FAIL  live API key pattern found in .env — scrub failed" >&2
  ERRORS=$((ERRORS + 1))
else
  pass "no live key patterns found in .env"
fi

if [ -n "$FALLBACK_PROVIDER_VAR" ]; then
  if grep -qx "${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault" "$ENV_FILE"; then
    pass "fallback placeholder confirmed in .env"
  else
    echo "FAIL  ${FALLBACK_PROVIDER_VAR} placeholder not found in .env — step 4.1 may have failed" >&2
    ERRORS=$((ERRORS + 1))
  fi
fi

[ "$ERRORS" -eq 0 ] || fail "${ERRORS} verification check(s) failed — review .env before starting the container"

# --- Step 9: Confirm ---

echo ""
echo "--- Vault confirmation ---"
agent-vault vault credential list --vault "${VAULT_NAME}"
agent-vault vault service list --vault "${VAULT_NAME}"
agent-vault agent list --vault "${VAULT_NAME}"
docker network inspect "${NETWORK_NAME}" --format '{{range .Containers}}{{.Name}} {{end}}'
echo ""
pass "provision-tenant-vault complete for ${TENANT_ID}"
echo "Next: return to onboard-tenant.md step 6.4 (copy tenant-contact-admin skill)"
