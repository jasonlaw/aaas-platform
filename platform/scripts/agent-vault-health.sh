#!/usr/bin/env bash
# Check Agent Vault container and API reachability.
# Exit 0 = healthy, exit 1 = one or more failures.

set -euo pipefail

pass() { printf 'PASS\t%s\n' "$1"; }
warn() { printf 'WARN\t%s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL\t%s\n' "$1"; ERRORS=$((ERRORS + 1)); }

WARNINGS=0
ERRORS=0
VAULT_MGMT_URL="${AGENT_VAULT_MGMT_URL:-http://localhost:14321}"

echo "Agent Vault health check"
echo "mgmt_url=$VAULT_MGMT_URL"
echo ""

# --- Container presence ---
if docker ps --filter name=agent-vault --filter status=running --format '{{.Names}}' \
    | grep -q '^agent-vault$'; then
  pass "agent_vault_container_running"
else
  fail "agent_vault_container_not_running"
fi

# --- Docker health status ---
HEALTH="$(docker inspect --format='{{.State.Health.Status}}' agent-vault 2>/dev/null || echo 'unknown')"
case "$HEALTH" in
  healthy)  pass "agent_vault_health_check:$HEALTH" ;;
  starting) warn "agent_vault_health_check:$HEALTH" ;;
  *)        fail "agent_vault_health_check:$HEALTH" ;;
esac

# --- Management API reachability ---
if command -v curl >/dev/null 2>&1; then
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 "$VAULT_MGMT_URL/health" 2>/dev/null || echo '000')"
  if [ "$HTTP_CODE" = "200" ]; then
    pass "agent_vault_mgmt_api_reachable:http_$HTTP_CODE"
  else
    fail "agent_vault_mgmt_api_unreachable:http_$HTTP_CODE"
  fi
else
  warn "curl_not_available:skipping_api_reachability_check"
fi

# --- MITM proxy port reachability ---
# curl's --proxytunnel treats a 407 response to CONNECT as a tunnel failure,
# not as an HTTP response. That means %{http_code} stays "000" even when the
# proxy is up and correctly demanding auth, so it cannot be used to detect a
# healthy proxy here. Read the CONNECT status line from verbose output instead.
if command -v curl >/dev/null 2>&1; then
  PROXY_VERBOSE="$(curl -s -o /dev/null -v \
    --connect-timeout 5 \
    --proxytunnel --proxy "http://localhost:14322" \
    "http://healthcheck.internal/" 2>&1 || true)"
  if echo "$PROXY_VERBOSE" | grep -q '^< HTTP/1\.[01] 407'; then
    pass "agent_vault_proxy_port_reachable:http_407"
  elif echo "$PROXY_VERBOSE" | grep -q '^< HTTP/1\.[01] 200'; then
    pass "agent_vault_proxy_port_reachable:http_200"
  else
    fail "agent_vault_proxy_port_unreachable"
  fi
else
  warn "curl_not_available:skipping_proxy_port_check"
fi

# --- CLI session check (non-blocking) ---
# agent-vault v0.39.0+ does not accept --addr/--address on subcommands; the
# CLI resolves the server from the saved session file (~/.agent-vault/session.json)
# established by `agent-vault auth login`. Do not add an address flag here.
if command -v agent-vault >/dev/null 2>&1; then
  # Every other network check in this script uses --connect-timeout; the CLI
  # binary has no equivalent flag, so wrap it in `timeout` instead. Without
  # this, a still-initializing or unreachable Agent Vault can hang this
  # check indefinitely — and since callers often redirect this script's
  # output to /dev/null, that hang produces no visible signal at all.
  if command -v timeout >/dev/null 2>&1; then
    if timeout 10 agent-vault vault list >/dev/null 2>&1; then
      pass "agent_vault_cli_authenticated"
    else
      warn "agent_vault_cli_not_authenticated_or_session_expired_or_timed_out"
    fi
  else
    if agent-vault vault list >/dev/null 2>&1; then
      pass "agent_vault_cli_authenticated"
    else
      warn "agent_vault_cli_not_authenticated_or_session_expired"
    fi
  fi
else
  warn "agent_vault_cli_not_installed_on_host"
fi

# --- Data directory ---
DATA_DIR="/opt/aaas/agent-vault/data"
if [ -d "$DATA_DIR" ]; then
  pass "agent_vault_data_dir_exists:$DATA_DIR"
else
  fail "agent_vault_data_dir_missing:$DATA_DIR"
fi

echo ""
echo "summary warn=$WARNINGS fail=$ERRORS"
[ "$ERRORS" -eq 0 ]