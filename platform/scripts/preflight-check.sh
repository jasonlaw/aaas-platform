#!/usr/bin/env bash
# Validate host/platform readiness before major AaaS operations.

set -euo pipefail

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/aaas}"
ERRORS=0
WARNINGS=0

pass() { printf 'PASS\t%s\n' "$1"; }
warn() { printf 'WARN\t%s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL\t%s\n' "$1"; ERRORS=$((ERRORS + 1)); }

echo "AaaS pre-flight check"
echo "platform_root=$PLATFORM_ROOT"
echo ""

command -v git >/dev/null 2>&1 && pass "git_available" || warn "git_not_found"
command -v docker >/dev/null 2>&1 && pass "docker_available" || fail "docker_not_found"
command -v opencode >/dev/null 2>&1 && pass "opencode_available" || warn "opencode_not_found"

[ -d "$INSTALL_ROOT" ] && pass "install_root_exists" || fail "missing_install_root:$INSTALL_ROOT"
[ -d "$PLATFORM_ROOT" ] && pass "platform_root_exists" || fail "missing_platform_root:$PLATFORM_ROOT"
[ -f "$PLATFORM_ROOT/VERSION" ] && pass "platform_version_exists" || fail "missing_platform_version"
[ -f "$PLATFORM_ROOT/AGENTS.md" ] && pass "agents_instructions_exist" || fail "missing_agents_md"
[ -f "$PLATFORM_ROOT/PLATFORM-REFERENCE.md" ] && pass "platform_reference_exists" || fail "missing_platform_reference_md"
[ -f "$PLATFORM_ROOT/tenants.yaml" ] && pass "tenant_registry_exists" || fail "missing_tenants_yaml"
[ -f "$PLATFORM_ROOT/docker/docker-compose.yaml" ] && pass "docker_compose_exists" || fail "missing_docker_compose"
[ -f "$PLATFORM_ROOT/reports/INDEX.jsonl" ] && pass "report_index_exists" || warn "missing_report_index"

if command -v docker >/dev/null 2>&1; then
  docker ps >/dev/null 2>&1 && pass "docker_responsive" || fail "docker_not_responsive"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files docker.service >/dev/null 2>&1; then
  systemctl is-enabled docker >/dev/null 2>&1 && pass "docker_enabled_at_boot" || fail "docker_not_enabled_at_boot"
else
  warn "docker_boot_enable_not_checked:no_systemd_docker_service"
fi

if command -v iptables >/dev/null 2>&1; then
  IPTABLES_VERSION="$(iptables --version 2>/dev/null || true)"
  echo "$IPTABLES_VERSION" | grep -q "legacy" && pass "iptables_legacy" || fail "iptables_not_legacy:$IPTABLES_VERSION"
else
  fail "iptables_not_found"
fi

# iptables-legacy does not prevent the Docker 29.x custom-bridge nftables
# gap (see docs/troubleshooting.md); check custom bridge networks directly.
if command -v docker >/dev/null 2>&1 && [ -x "$PLATFORM_ROOT/scripts/fix-docker-nftables.sh" ]; then
  "$PLATFORM_ROOT/scripts/fix-docker-nftables.sh" --check >/dev/null 2>&1 \
    && pass "docker_custom_bridge_nftables_rules_ok" \
    || warn "docker_custom_bridge_nftables_rules_missing:run $PLATFORM_ROOT/scripts/fix-docker-nftables.sh --apply"
fi

if command -v jq >/dev/null 2>&1; then
  pass "jq_available"
else
  warn "jq_not_found:report analysis will use fallback summaries"
fi

# Tenant image — fail if not built; every onboard depends on it
if command -v docker >/dev/null 2>&1; then
  if docker image inspect hermes-tenant:latest >/dev/null 2>&1; then
    pass "hermes_tenant_image_exists"
  else
    fail "hermes_tenant_image_missing:run setup-platform.sh --build-image before onboarding tenants"
  fi
fi

# Agent Vault — warn only; setup may not have been run yet
if command -v docker >/dev/null 2>&1; then
  if docker ps --filter name=agent-vault --filter status=running --format '{{.Names}}' \
      | grep -q '^agent-vault$'; then
    VAULT_HEALTH="$(docker inspect --format='{{.State.Health.Status}}' agent-vault 2>/dev/null || echo 'unknown')"
    case "$VAULT_HEALTH" in
      healthy)  pass "agent_vault_running_and_healthy" ;;
      starting) warn "agent_vault_starting:health_check_pending" ;;
      *)        warn "agent_vault_unhealthy:status=$VAULT_HEALTH" ;;
    esac
  else
    warn "agent_vault_not_running:credential_proxy_unavailable_run_setup-agent-vault_sop"
  fi
fi

# Admin Hermes — two separate checks:
# (a) Whether admin Hermes is configured at all. This is a WARN during
#     general pre-flight but becomes relevant context for the business
#     intelligence sub-agent (which calls `hermes -z` from the admin
#     install): if admin Hermes is not configured, the sub-agent will
#     fail and silently fall back to cold generation, with no clear
#     diagnostic. Surfacing this here gives operators a diagnosable
#     signal before they hit the silent fallback during onboarding.
# (b) SOUL.md/config.yaml drift against their shipped templates —
#     see check-admin-drift.sh's own header for why this can't just be
#     a plain diff. Warn-only (not fail): a stale admin config is a real
#     problem to surface but shouldn't block every other pre-flight use
#     of this script. SKIP output (admin not set up yet) is expected.
if [ -f "$PLATFORM_ROOT/admin/config.yaml" ] && [ -f "$PLATFORM_ROOT/admin/.env" ]; then
  pass "admin_hermes_configured"
else
  warn "admin_hermes_not_configured:run 'setup-admin-hermes' skill before onboarding tenants (tenant agents contact admin Hermes for support and LLM key changes)"
fi

if [ -x "$PLATFORM_ROOT/scripts/check-admin-drift.sh" ]; then
  # Assigning a failing command substitution directly (DRIFT_OUTPUT="$(...)")
  # would trip this script's own `set -e` and exit immediately, before
  # DRIFT_STATUS=$? ever ran — wrapping the assignment in the `if` condition
  # itself is what keeps `set -e` from firing on a non-zero exit here.
  if DRIFT_OUTPUT="$("$PLATFORM_ROOT/scripts/check-admin-drift.sh" 2>&1)"; then
    DRIFT_STATUS=0
  else
    DRIFT_STATUS=$?
  fi
  if [ "$DRIFT_STATUS" -ne 0 ]; then
    warn "admin_hermes_config_drift_detected:run $PLATFORM_ROOT/scripts/check-admin-drift.sh for details"
  elif printf '%s\n' "$DRIFT_OUTPUT" | grep -q '^WARN\t'; then
    warn "admin_hermes_config_differs_from_template:run $PLATFORM_ROOT/scripts/check-admin-drift.sh for details"
  else
    pass "admin_hermes_config_matches_template_or_not_yet_set_up"
  fi
fi

echo ""
echo "summary warn=$WARNINGS fail=$ERRORS"
[ "$ERRORS" -eq 0 ]