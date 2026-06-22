#!/usr/bin/env bash
# AaaS tenant harness check.
# Runs deterministic checks that prove a tenant is structurally ready before
# the admin agent declares onboarding, upgrade, or troubleshooting complete.

set -euo pipefail

TENANT_ID="${1:-}"
PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
COMPOSE_FILE="$PLATFORM_ROOT/docker/docker-compose.yaml"
TENANTS_FILE="$PLATFORM_ROOT/tenants.yaml"
SERVICE="hermes_$TENANT_ID"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

usage() {
  echo "Usage: $0 {tenant-id}"
}

maybe_reexec_with_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    return
  fi

  # Tenant files are intentionally owned by UID 10000. A non-root operator may
  # be able to see the directory entry but not inspect the files inside it.
  if [ -e "$TENANT_DIR" ] && { [ ! -x "$TENANT_DIR" ] || [ ! -r "$TENANT_DIR" ] || [ ! -r "$TENANT_DIR/harness.yaml" ] || [ ! -r "$TENANT_DIR/.env" ]; }; then
    echo "Tenant files are not readable by $(id -un); rerunning harness check with sudo..." >&2
    exec sudo -E "$0" "$TENANT_ID"
  fi
}

record() {
  local status="$1"
  local check="$2"
  local detail="${3:-}"

  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
  esac

  if [ -n "$detail" ]; then
    printf '%s\t%s\t%s\n' "$status" "$check" "$detail"
  else
    printf '%s\t%s\n' "$status" "$check"
  fi
}

exists_file() {
  local path="$1"
  local name="$2"
  [ -f "$path" ] && record PASS "$name" "$path" || record FAIL "$name" "missing: $path"
}

exists_dir() {
  local path="$1"
  local name="$2"
  [ -d "$path" ] && record PASS "$name" "$path" || record FAIL "$name" "missing: $path"
}

contains() {
  local path="$1"
  local pattern="$2"
  local name="$3"
  if [ ! -f "$path" ]; then
    record FAIL "$name" "missing file: $path"
  elif grep -Eq "$pattern" "$path"; then
    record PASS "$name"
  else
    record FAIL "$name" "pattern not found: $pattern"
  fi
}

owned_by_hermes() {
  local path="$1"
  local name="$2"
  local owner

  if [ ! -e "$path" ]; then
    record FAIL "$name" "missing: $path"
    return
  fi

  owner="$(stat -c '%u:%g' "$path" 2>/dev/null || true)"
  if [ "$owner" = "10000:10000" ]; then
    record PASS "$name"
  else
    record FAIL "$name" "expected 10000:10000, got ${owner:-unknown}: $path"
  fi
}

if [ -z "$TENANT_ID" ]; then
  usage
  exit 2
fi

maybe_reexec_with_sudo

echo "AaaS tenant harness check"
echo "tenant_id=$TENANT_ID"
echo "platform_root=$PLATFORM_ROOT"
echo ""

exists_dir "$TENANT_DIR" "tenant_directory"
exists_dir "$TENANT_DIR/memories" "tenant_memories_directory"
exists_dir "$TENANT_DIR/files/assets" "tenant_assets_directory"
exists_dir "$TENANT_DIR/files/uploads" "tenant_uploads_directory"
exists_dir "$TENANT_DIR/files/generated" "tenant_generated_directory"

exists_file "$TENANT_DIR/config.yaml" "tenant_config"
exists_file "$TENANT_DIR/.env" "tenant_env"
exists_file "$TENANT_DIR/.env.template" "tenant_env_template"
exists_file "$TENANT_DIR/SOUL.md" "tenant_soul"
exists_file "$TENANT_DIR/memories/MEMORY.md" "tenant_brand_memory_seed"
exists_file "$TENANT_DIR/memories/USER.md" "tenant_owner_memory_seed"
exists_file "$TENANT_DIR/harness.yaml" "tenant_harness_manifest"
exists_file "$TENANT_DIR/ACCEPTANCE.md" "tenant_acceptance_record"

contains "$TENANT_DIR/config.yaml" 'provider:[[:space:]]*mnemosyne' "config_uses_mnemosyne"
contains "$TENANT_DIR/config.yaml" 'memory_enabled:[[:space:]]*false' "config_disables_native_memory"
contains "$TENANT_DIR/config.yaml" 'user_profile_enabled:[[:space:]]*false' "config_disables_native_user_profile"
contains "$TENANT_DIR/.env" '^TELEGRAM_ALLOWED_USERS=[0-9, ]+$' "env_has_allowed_telegram_users"
contains "$TENANT_DIR/.env" '^MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data$' "env_pins_mnemosyne_data"
contains "$TENANT_DIR/SOUL.md" 'never perform irreversible actions' "soul_requires_owner_confirmation"
contains "$TENANT_DIR/SOUL.md" '~/files/generated' "soul_directs_generated_files"
contains "$TENANT_DIR/SOUL.md" '~/files/uploads' "soul_directs_uploaded_files"
contains "$TENANT_DIR/harness.yaml" '^tenant_harness_version:[[:space:]]*1' "manifest_has_harness_version"
contains "$TENANT_DIR/harness.yaml" '^verification_profile:' "manifest_has_verification_profile"
contains "$TENANT_DIR/harness.yaml" '^fixed_safety_profile:[[:space:]]*"?_fixed-safety-v1"?' "manifest_has_fixed_safety_profile"
contains "$TENANT_DIR/SOUL.md" 'never perform irreversible actions' "soul_has_fixed_safety_language"
exists_file "$PLATFORM_ROOT/evals/tenant-agent/generated/$TENANT_ID-v1.yaml" "tenant_generated_eval_file"

owned_by_hermes "$TENANT_DIR" "tenant_directory_owner_is_10000"
owned_by_hermes "$TENANT_DIR/harness.yaml" "tenant_harness_owner_is_10000"
owned_by_hermes "$TENANT_DIR/ACCEPTANCE.md" "tenant_acceptance_owner_is_10000"

if [ -f "$TENANT_DIR/.env" ] && grep -Eq '(sk-[A-Za-z0-9_-]{12,}|xox[baprs]-|[0-9]{8,}:[A-Za-z0-9_-]{20,})' "$TENANT_DIR/.env.template" 2>/dev/null; then
  record FAIL "env_template_has_secret_like_value" ".env.template must contain keys only"
else
  record PASS "env_template_has_no_obvious_secrets"
fi

contains "$COMPOSE_FILE" "^  $SERVICE:" "compose_has_tenant_service"
contains "$COMPOSE_FILE" "$TENANT_DIR:/opt/data" "compose_mounts_tenant_data"
contains "$COMPOSE_FILE" "$TENANT_DIR/files:/home/hermes/files" "compose_mounts_tenant_files"
contains "$COMPOSE_FILE" "$TENANT_DIR/.env" "compose_uses_tenant_env"
contains "$TENANTS_FILE" "id:[[:space:]]*$TENANT_ID|tenant_id:[[:space:]]*$TENANT_ID|$TENANT_ID" "tenant_registry_mentions_tenant"

if command -v docker >/dev/null 2>&1; then
  if docker ps --filter "name=^/${SERVICE}$" --format '{{.Names}}' 2>/dev/null | grep -qx "$SERVICE"; then
    record PASS "container_running" "$SERVICE"
  else
    record FAIL "container_running" "$SERVICE not running"
  fi

  if docker exec "$SERVICE" sh -lc 'test -d /opt/data && test -d /home/hermes/files' >/dev/null 2>&1; then
    record PASS "container_mounts_visible"
  else
    record WARN "container_mounts_visible" "container unavailable or mounts not visible"
  fi

  if docker exec "$SERVICE" sh -lc 'test -n "$MNEMOSYNE_DATA_DIR" && test "$MNEMOSYNE_DATA_DIR" = "/opt/data/mnemosyne/data"' >/dev/null 2>&1; then
    record PASS "container_mnemosyne_env"
  else
    record WARN "container_mnemosyne_env" "MNEMOSYNE_DATA_DIR not visible inside running container"
  fi

  if docker exec "$SERVICE" sh -lc 'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org' 2>/dev/null | grep -Eq '^(200|301|302|404)$'; then
    record PASS "container_outbound_https"
  else
    record WARN "container_outbound_https" "Telegram API HTTPS check did not return expected code"
  fi
else
  record WARN "docker_available" "docker command not found; skipped runtime checks"
fi

echo ""
echo "summary pass=$PASS_COUNT warn=$WARN_COUNT fail=$FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
