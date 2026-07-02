#!/usr/bin/env bash
# Scaffold (or backfill) the knowledge vault for one tenant.
#
# Replaces the 5-command vault scaffold block repeated verbatim in:
#   onboard-tenant.md step 4.2
#   update-tenant.md step 7.1
#   upgrade-tenants.md step 3 (vault backfill sub-step)
#   troubleshoot-tenant.md "Knowledge Vault Missing" recovery path
#
# Idempotent: safe to re-run on a tenant that already has a vault — vault-init-tenant.sh
# never overwrites existing notes (it skips files that already exist).
# Also ensures the vault/scripts directory exists and the scaffolder is in place.
#
# Usage:
#   backfill-tenant-vault.sh {tenant-id} "{business-name}"
#
# Environment overrides (for testing):
#   PLATFORM_ROOT   (default: /opt/aaas/platform)
#   TENANT_ROOT     (default: /opt/aaas/tenants)

set -euo pipefail

TENANT_ID="${1:-}"
BUSINESS_NAME="${2:-}"
PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"

usage() {
  echo "Usage: $0 {tenant-id} \"{business-name}\"" >&2
}

fail() {
  echo "FAIL  $1" >&2
  exit 1
}

if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  usage
  fail "missing or invalid tenant-id"
fi

if [ -z "$BUSINESS_NAME" ]; then
  usage
  fail "missing business-name — required to render the vault README correctly"
fi

TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
SCAFFOLDER_SRC="$PLATFORM_ROOT/tenant-hermes/scripts/vault-init-tenant.sh"
SCAFFOLDER_DST="$TENANT_DIR/scripts/vault-init-tenant.sh"

[ -d "$TENANT_DIR" ] \
  || fail "tenant directory not found: $TENANT_DIR"

[ -f "$SCAFFOLDER_SRC" ] \
  || fail "vault-init-tenant.sh not found at $SCAFFOLDER_SRC — is the platform up to date?"

mkdir -p "$TENANT_DIR/scripts"
cp "$SCAFFOLDER_SRC" "$SCAFFOLDER_DST"
chmod +x "$SCAFFOLDER_DST"

TENANT_DIR="$TENANT_DIR" BUSINESS_NAME="$BUSINESS_NAME" \
  "$SCAFFOLDER_DST" "$TENANT_ID"

echo "PASS  knowledge vault scaffolded at $TENANT_DIR/vault/"
echo "NOTE  also add the vault -> /home/hermes/vault mount to docker-compose.yaml if it is missing for this tenant"
