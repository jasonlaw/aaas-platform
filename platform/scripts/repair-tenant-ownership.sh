#!/usr/bin/env bash
# Repair ownership and host-side read access on a tenant volume.
#
# Replaces the two-command block repeated verbatim in onboard-tenant.md (step 7),
# update-tenant.md (step 8), and upgrade-tenants.md (step 3 ownership sub-step).
#
# Why two commands are always required:
#   chown -R 10000:10000   — sets ownership for the Hermes container user (UID 10000).
#                            Without this, mounted /opt/data paths fail with
#                            Permission denied inside the container.
#   chmod -R go+rX         — restores host-side read access for the operator/
#                            automation user who runs `docker compose` CLI commands.
#                            Without this, `docker compose up` can fail to read
#                            .env even though the daemon itself runs as root,
#                            because the CLI parses env_file client-side.
#   Both must be recursive (-R). A top-level-only chmod misses subdirectories
#   the tenant container creates at runtime (Mnemosyne data, logs, etc., owned
#   by UID 10000 with a restrictive default umask), which silently revert to
#   unreadable on the host even though the top-level directory looks fine.
#
# Usage:
#   repair-tenant-ownership.sh {tenant-id}
#
# Environment overrides (for testing):
#   TENANT_ROOT   (default: /opt/aaas/tenants)

set -euo pipefail

TENANT_ID="${1:-}"
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

[ -d "$TENANT_DIR" ] \
  || fail "tenant directory not found: $TENANT_DIR"

sudo chown -R 10000:10000 "$TENANT_DIR"
sudo chmod -R go+rX "$TENANT_DIR"

echo "PASS  ownership repaired: $TENANT_DIR (chown -R 10000:10000, chmod -R go+rX)"
