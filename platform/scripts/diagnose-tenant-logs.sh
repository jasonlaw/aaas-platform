#!/usr/bin/env bash
# Diagnose tenant container logs using the platform's known error vocabulary.
#
# Replaces free-form LLM log triage in troubleshoot-tenant.md step 7.
# Pattern-matches against the exact check names from check-tenant.sh,
# the recovery paths in troubleshoot-tenant.md, and agent-vault-health.sh
# output — so every match maps directly to a named recovery path the agent
# can invoke without re-reading logs in its context window.
#
# Outputs one line per finding:
#   CATEGORY  check_name  human-readable detail
#
# Categories:
#   permission      chown/chmod repair needed
#   vault           Agent Vault / proxy / credential issue
#   mnemosyne       Memory not active, wrong data dir, or seed failed
#   network         Outbound connectivity or iptables problem
#   config          config.yaml or .env value wrong
#   plugin          tenant-installed plugin missing or failed to reconcile
#   container       Container stopped/crashed or entrypoint issue
#   none            No known error patterns found — escalate to operator
#
# Usage:
#   diagnose-tenant-logs.sh {tenant-id} [tail-lines]
#
#   tail-lines defaults to 200. Use a higher value for intermittent issues.
#
# Environment overrides:
#   PLATFORM_ROOT   (default: /opt/aaas/platform)

set -euo pipefail

TENANT_ID="${1:-}"
TAIL_LINES="${2:-200}"
PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"

usage() {
  echo "Usage: $0 {tenant-id} [tail-lines]" >&2
}

if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  usage
  exit 2
fi

SERVICE="hermes_${TENANT_ID}"

# Check the container exists before trying to read logs
if ! docker ps -a --filter "name=^/${SERVICE}$" --format '{{.Names}}' 2>/dev/null \
    | grep -qx "$SERVICE"; then
  echo "FAIL  container_not_found  $SERVICE does not exist — check docker-compose.yaml"
  exit 1
fi

LOGS="$(docker logs "$SERVICE" --tail "$TAIL_LINES" 2>&1 || true)"

FINDINGS=0

emit() {
  local category="$1"
  local check="$2"
  local detail="$3"
  printf '%-14s  %-42s  %s\n' "$category" "$check" "$detail"
  FINDINGS=$((FINDINGS + 1))
}

# --- Permission errors ---
# Maps to: troubleshoot-tenant.md "Permission Denied In Logs"
# Fix: sudo chown -R 10000:10000 + sudo chmod -R go+rX

if echo "$LOGS" | grep -qiE "permission denied|operation not permitted"; then
  emit "permission" "permission_denied_in_logs" \
    "Fix: sudo chown -R 10000:10000 /opt/aaas/tenants/${TENANT_ID}/ && sudo chmod -R go+rX /opt/aaas/tenants/${TENANT_ID}/"
fi

# --- Agent Vault / proxy errors ---
# Maps to: manage-agent-vault.md, incidents/agent-vault-failure.md
# Patterns: proxy auth failure (407 unexpected), SSL MITM cert not trusted,
#           connection refused on proxy port, vault token rejected

if echo "$LOGS" | grep -qiE "407|proxy.auth|proxy-authorization"; then
  emit "vault" "vault_proxy_auth_failed" \
    "Proxy token rejected — check AGENT_VAULT_TOKEN in .env and run agent-vault-health.sh"
fi

if echo "$LOGS" | grep -qiE "ssl.*verify|certificate.*verify|ssl.*cert|CERTIFICATE_VERIFY_FAILED"; then
  emit "vault" "vault_ssl_cert_untrusted" \
    "Agent Vault MITM CA not trusted — check SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt in .env"
fi

if echo "$LOGS" | grep -qiE "connection refused.*14322|14322.*connection refused|proxy.*connect.*refused"; then
  emit "vault" "vault_proxy_port_unreachable" \
    "Agent Vault proxy sidecar not reachable — check: docker ps | grep agent-vault-proxy-${TENANT_ID}"
fi

if echo "$LOGS" | grep -qiE "routed-via-agent-vault|invalid.*api.key|authentication.*failed|401 unauthorized" \
    && echo "$LOGS" | grep -qiE "api\.openai\.com|api\.anthropic\.com|openrouter\.ai|api\.nous\.ai|opencode\.ai"; then
  emit "vault" "vault_key_not_injected" \
    "Real API key not injected by proxy — run: agent-vault vault credential list --vault ${TENANT_ID}-vault"
fi

# --- Mnemosyne errors ---
# Maps to: troubleshoot-tenant.md "Mnemosyne Not Active Or Not Seeded"
# Fix: check MNEMOSYNE_DATA_DIR, reinstall via onboarding step 12, re-seed

if echo "$LOGS" | grep -qiE "mnemosyne.*not.*found|mnemosyne.*error|memory.*provider.*not.*configured"; then
  emit "mnemosyne" "mnemosyne_not_active" \
    "Reinstall: docker exec -e HERMES_HOME=/opt/data $SERVICE mnemosyne-hermes install"
fi

if echo "$LOGS" | grep -qiE "MNEMOSYNE_DATA_DIR|mnemosyne.*data.*dir|mnemosyne.*path"; then
  emit "mnemosyne" "mnemosyne_data_dir_mismatch" \
    "Check: docker exec $SERVICE sh -lc 'echo \$MNEMOSYNE_DATA_DIR' — must be /opt/data/mnemosyne/data"
fi

if echo "$LOGS" | grep -qiE "seed.*fail|memory.*seed|failed to store"; then
  emit "mnemosyne" "mnemosyne_seed_failed" \
    "Re-seed: docker exec $SERVICE python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/MEMORY.md fact"
fi

# --- Network / iptables errors ---
# Maps to: troubleshoot-tenant.md "No Outbound Network"
# Fix: verify iptables legacy, check DOCKER-FORWARD chain

if echo "$LOGS" | grep -qiE "network.*unreachable|no route to host|name.*resolution.*fail|dns.*fail"; then
  emit "network" "outbound_network_failed" \
    "Check: iptables --version (must show legacy) and: sudo iptables -L DOCKER-FORWARD -n | head -10"
fi

if echo "$LOGS" | grep -qiE "telegram.*timeout|api\.telegram\.org.*fail|telegram.*connect"; then
  emit "network" "telegram_unreachable" \
    "Test: docker exec $SERVICE ping -c 2 -W 3 api.telegram.org"
fi

# --- Config errors ---
# Maps to: troubleshoot-tenant.md "Invalid Config", validate-tenant-config.sh
# Fix: edit config.yaml and force-recreate (with operator confirm)

if echo "$LOGS" | grep -qiE "home_chat_id|invalid.*config|config.*parse.*error|missing.*provider"; then
  emit "config" "config_parse_error" \
    "Run: /opt/aaas/platform/scripts/validate-tenant-config.sh ${TENANT_ID}"
fi

if echo "$LOGS" | grep -qiE "memory\.provider|native.*memory|user_profile"; then
  emit "config" "config_memory_settings_wrong" \
    "Ensure config.yaml has: memory.provider: mnemosyne, memory_enabled: false, user_profile_enabled: false"
fi

# --- Plugin errors ---
# Maps to: troubleshoot-tenant.md "Tenant-Installed Plugin Missing Or Not Working"

if echo "$LOGS" | grep -qiE "\[reconcile-plugins\].*fail|\[reconcile-plugins\].*error|plugin.*not.*found|ModuleNotFoundError|ImportError"; then
  emit "plugin" "plugin_reconcile_failed" \
    "Check: docker exec $SERVICE cat /opt/data/installed-plugins.yaml — then force reconcile: docker exec $SERVICE /opt/data/scripts/reconcile-plugins.sh"
fi

# --- Container / entrypoint errors ---
# Maps to: troubleshoot-tenant.md "Container Missing Or Stopped"

if echo "$LOGS" | grep -qiE "gateway.*exit|entrypoint.*fail|exec.*format.*error"; then
  emit "container" "entrypoint_error" \
    "Image may be wrong or entrypoint script missing — check: docker exec $SERVICE ls /opt/data/scripts/tenant-entrypoint.sh"
fi

CONTAINER_STATUS="$(docker inspect --format='{{.State.Status}}' "$SERVICE" 2>/dev/null || echo 'unknown')"
if [ "$CONTAINER_STATUS" != "running" ]; then
  emit "container" "container_not_running" \
    "Status: $CONTAINER_STATUS — start with: docker compose up -d $SERVICE"
fi

# --- Summary ---
echo ""
if [ "$FINDINGS" -eq 0 ]; then
  emit "none" "no_known_patterns_matched" \
    "No recognised error patterns in last $TAIL_LINES log lines — escalate to operator with full logs"
  echo ""
  echo "summary  findings=0  action=escalate_to_operator"
  exit 0
fi

echo "summary  findings=$FINDINGS  container_status=$CONTAINER_STATUS"
echo ""
echo "Next: run check-tenant.sh ${TENANT_ID} and follow the named recovery path in troubleshoot-tenant.md"
