#!/usr/bin/env bash
# Validate tenant config and harness contract before container start/restart.

set -euo pipefail

TENANT_ID="${1:-}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
CONFIG="$TENANT_DIR/config.yaml"
HARNESS="$TENANT_DIR/harness.yaml"
ERRORS=0

fail() {
  printf 'FAIL\t%s\n' "$1"
  ERRORS=$((ERRORS + 1))
}

pass() {
  printf 'PASS\t%s\n' "$1"
}

contains() {
  local path="$1"
  local pattern="$2"
  local name="$3"

  if [ ! -f "$path" ]; then
    fail "$name:missing_file:$path"
  elif grep -Eq "$pattern" "$path"; then
    pass "$name"
  else
    fail "$name:missing_pattern:$pattern"
  fi
}

owned_by_hermes() {
  local path="$1"
  local name="$2"
  local owner

  if [ ! -e "$path" ]; then
    fail "$name:missing:$path"
    return
  fi

  owner="$(stat -c '%u:%g' "$path" 2>/dev/null || true)"
  if [ "$owner" = "10000:10000" ]; then
    pass "$name"
  else
    fail "$name:expected_owner_10000_10000:actual_${owner:-unknown}:$path"
  fi
}

if [ -z "$TENANT_ID" ]; then
  echo "Usage: $0 {tenant-id}"
  exit 2
fi

echo "AaaS tenant config validation"
echo "tenant_id=$TENANT_ID"
echo ""

[ -d "$TENANT_DIR" ] && pass "tenant_directory_exists" || fail "tenant_directory_missing:$TENANT_DIR"

contains "$CONFIG" '^_config_version:[[:space:]]*1' "config_version_1"
contains "$CONFIG" '^model:' "config_has_model_section"
contains "$CONFIG" 'provider:[[:space:]]*mnemosyne' "config_memory_provider_mnemosyne"
contains "$CONFIG" 'memory_enabled:[[:space:]]*false' "config_native_memory_disabled"
contains "$CONFIG" 'user_profile_enabled:[[:space:]]*false' "config_native_user_profile_disabled"
contains "$CONFIG" 'home_chat_id:[[:space:]]*["'"'"']["'"'"']' "config_home_chat_empty"

contains "$HARNESS" '^tenant_harness_version:[[:space:]]*1' "harness_version_1"
contains "$HARNESS" "^tenant_id:[[:space:]]*\"?$TENANT_ID\"?" "harness_tenant_id_matches"
contains "$HARNESS" '^verification_profile:' "harness_has_verification_profile"

owned_by_hermes "$TENANT_DIR" "tenant_directory_owner_is_10000"
owned_by_hermes "$HARNESS" "harness_owner_is_10000"
owned_by_hermes "$TENANT_DIR/ACCEPTANCE.md" "acceptance_owner_is_10000"

echo ""
echo "summary fail=$ERRORS"
[ "$ERRORS" -eq 0 ]