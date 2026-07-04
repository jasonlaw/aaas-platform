#!/usr/bin/env bash
# Copy all tenant runtime scripts into a tenant's scripts/ directory.
#
# Replaces the multi-cp + multi-chmod block that previously appeared in full in:
#   onboard-tenant.md steps 6.2, 6.2.1, and 6.2.2
#   upgrade-tenants.md step 3 (tenant-install.sh/reconcile-plugins.sh backfill sub-step)
#   troubleshoot-tenant.md "Tenant-Installed Plugin Missing" recovery path
#
# Scripts installed:
#   skill-verify.sh       — tenant agent calls from /opt/data/scripts/ at runtime
#   tenant-install.sh     — tenant agent calls to install pip/binary plugins
#   reconcile-plugins.sh  — runs automatically via tenant-entrypoint.sh on start
#   tenant-entrypoint.sh  — compose service command (replaces bare `gateway run`)
#   seed-mnemosyne.py     — called by onboard-tenant step 13 and update-tenant step 5
#   seed-vault-context.py — called by onboard-tenant step 4.2 to write sub-agent vault notes
#
# Idempotent: no-op for each file that is already present and identical to the source.
# Non-identical files are overwritten (forward-upgrade semantics — the platform copy
# is always authoritative; a tenant-local modification would be silently lost, which
# is intentional: these are platform-managed scripts, not tenant-editable files).
#
# Usage:
#   install-tenant-scripts.sh {tenant-id}
#
# Environment overrides (for testing):
#   PLATFORM_ROOT   (default: /opt/aaas/platform)
#   TENANT_ROOT     (default: /opt/aaas/tenants)

set -euo pipefail

TENANT_ID="${1:-}"
PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"

usage() {
  echo "Usage: $0 {tenant-id}" >&2
}

fail() {
  echo "FAIL  $1" >&2
  exit 1
}

if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  usage
  fail "missing or invalid tenant-id"
fi

TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
SCRIPTS_SRC="$PLATFORM_ROOT/tenant-hermes/scripts"
SCRIPTS_DST="$TENANT_DIR/scripts"

[ -d "$TENANT_DIR" ] \
  || fail "tenant directory not found: $TENANT_DIR"

[ -d "$SCRIPTS_SRC" ] \
  || fail "platform scripts directory not found: $SCRIPTS_SRC — is the platform up to date?"

mkdir -p "$SCRIPTS_DST"

INSTALLED=0
SKIPPED=0

install_script() {
  local name="$1"
  local src="$SCRIPTS_SRC/$name"
  local dst="$SCRIPTS_DST/$name"

  [ -f "$src" ] || { echo "WARN  $name not found in $SCRIPTS_SRC — skipping"; return; }

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    echo "SKIP  $name (already up to date)"
    SKIPPED=$((SKIPPED + 1))
  else
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "PASS  $name installed"
    INSTALLED=$((INSTALLED + 1))
  fi
}

install_script "skill-verify.sh"
install_script "tenant-install.sh"
install_script "reconcile-plugins.sh"
install_script "tenant-entrypoint.sh"
install_script "seed-mnemosyne.py"
install_script "seed-vault-context.py"

echo ""
echo "PASS  $INSTALLED installed, $SKIPPED already up to date — scripts at $SCRIPTS_DST"
echo "NOTE  if tenant compose service command still reads 'gateway run', update it to"
echo "      /opt/data/scripts/tenant-entrypoint.sh and recreate the container"
