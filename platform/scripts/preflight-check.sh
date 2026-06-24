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

if command -v jq >/dev/null 2>&1; then
  pass "jq_available"
else
  warn "jq_not_found:report analysis will use fallback summaries"
fi

echo ""
echo "summary warn=$WARNINGS fail=$ERRORS"
[ "$ERRORS" -eq 0 ]
