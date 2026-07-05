#!/usr/bin/env bash
# AaaS tenant harness check.
# Runs deterministic checks that prove a tenant is structurally ready before
# the admin agent declares onboarding, upgrade, or troubleshooting complete.

set -euo pipefail

TENANT_ID="${1:-}"

usage() {
  echo "Usage: $0 {tenant-id}"
}

# Guard against the id being an accidental flag (e.g. a caller forwarding
# "--build-image" or another CLI option instead of a real tenant id). Every
# check below derives its path from TENANT_ID, so a bad value here silently
# fans out into dozens of unrelated-looking FAILs instead of one clear error.
if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  echo "Error: missing or invalid tenant id: '${TENANT_ID}'" >&2
  usage >&2
  exit 1
fi

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
COMPOSE_FILE="$PLATFORM_ROOT/docker/docker-compose.yaml"
TENANTS_FILE="$PLATFORM_ROOT/tenants.yaml"
SERVICE="hermes_$TENANT_ID"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

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

service_contains() {
  local service="$1"
  local pattern="$2"
  local name="$3"

  if [ ! -f "$COMPOSE_FILE" ]; then
    record FAIL "$name" "missing file: $COMPOSE_FILE"
  elif awk -v service="  ${service}:" -v pattern="$pattern" '
    $0 == service { in_service=1; next }
    in_service && /^  [^[:space:]][^:]*:/ { in_service=0 }
    in_service && $0 ~ pattern { found=1 }
    END { exit found ? 0 : 1 }
  ' "$COMPOSE_FILE"; then
    record PASS "$name"
  else
    record FAIL "$name" "pattern not found in $service service: $pattern"
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

maybe_reexec_with_sudo

echo "AaaS tenant harness check"
echo "tenant_id=$TENANT_ID"
echo "platform_root=$PLATFORM_ROOT"
echo ""

exists_file "$PLATFORM_ROOT/tenant-hermes/evals/_skill-verification-primitives-v1.yaml" "platform_skill_verification_primitives"

exists_dir "$TENANT_DIR" "tenant_directory"
exists_dir "$TENANT_DIR/memories" "tenant_memories_directory"
exists_dir "$TENANT_DIR/files/assets" "tenant_assets_directory"
exists_dir "$TENANT_DIR/files/uploads" "tenant_uploads_directory"
exists_dir "$TENANT_DIR/files/generated" "tenant_generated_directory"
exists_dir "$TENANT_DIR/vault" "tenant_knowledge_vault_directory"
exists_file "$TENANT_DIR/vault/README.md" "tenant_knowledge_vault_readme"

exists_file "$TENANT_DIR/config.yaml" "tenant_config"
exists_file "$TENANT_DIR/.env" "tenant_env"
exists_file "$TENANT_DIR/.env.template" "tenant_env_template"
exists_file "$TENANT_DIR/SOUL.md" "tenant_soul"
exists_file "$TENANT_DIR/files/assets/business-data.md" "tenant_business_data_file"
exists_file "$TENANT_DIR/memories/MEMORY.md" "tenant_brand_memory_seed"
exists_file "$TENANT_DIR/memories/USER.md" "tenant_owner_memory_seed"
exists_file "$TENANT_DIR/harness.yaml" "tenant_harness_manifest"
exists_file "$TENANT_DIR/ACCEPTANCE.md" "tenant_acceptance_record"

# Plugin-persistence scripts (onboard-tenant.md step 6.2.1 / upgrade-tenants.md
# backfill). Without these, tenant-installed pip packages/binaries silently
# vanish on the next --force-recreate with no error pointing at the cause
# (see docs/architecture.md's "Tenant Plugin Persistence" section) — this is
# a functional gap, not just a missing file, so it gets its own named check
# rather than folding into the generic skill-verify.sh checks above.
if [ -x "$TENANT_DIR/scripts/tenant-install.sh" ] \
  && [ -x "$TENANT_DIR/scripts/reconcile-plugins.sh" ] \
  && [ -x "$TENANT_DIR/scripts/tenant-entrypoint.sh" ]; then
  record PASS "tenant_scripts_present"
else
  record FAIL "tenant_scripts_present" "missing or not executable: one or more of scripts/{tenant-install,reconcile-plugins,tenant-entrypoint}.sh under $TENANT_DIR — back-fill per onboard-tenant.md step 6.2.1 / upgrade-tenants.md"
fi

contains "$TENANT_DIR/config.yaml" 'provider:[[:space:]]*mnemosyne' "config_uses_mnemosyne"
contains "$TENANT_DIR/config.yaml" 'memory_enabled:[[:space:]]*false' "config_disables_native_memory"
contains "$TENANT_DIR/config.yaml" 'user_profile_enabled:[[:space:]]*false' "config_disables_native_user_profile"
contains "$TENANT_DIR/.env" '^TELEGRAM_ALLOWED_USERS=[0-9, ]+$' "env_has_allowed_telegram_users"
contains "$TENANT_DIR/.env" '^MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data$' "env_pins_mnemosyne_data"
contains "$TENANT_DIR/SOUL.md" 'BEGIN PLATFORM RULES' "soul_has_platform_rules_begin_marker"
contains "$TENANT_DIR/SOUL.md" 'END PLATFORM RULES' "soul_has_platform_rules_end_marker"
contains "$TENANT_DIR/SOUL.md" 'BEGIN TENANT RULES' "soul_has_tenant_rules_begin_marker"
contains "$TENANT_DIR/SOUL.md" 'END TENANT RULES' "soul_has_tenant_rules_end_marker"
contains "$TENANT_DIR/SOUL.md" 'try to work it out yourself' "soul_has_self_improvement_conduct"
contains "$TENANT_DIR/SOUL.md" 'short progress update' "soul_has_progress_reporting_conduct"
contains "$TENANT_DIR/SOUL.md" '/home/hermes/files/generated' "soul_directs_generated_files"
contains "$TENANT_DIR/SOUL.md" '/home/hermes/files/uploads' "soul_directs_uploaded_files"
contains "$TENANT_DIR/SOUL.md" '/home/hermes/vault' "soul_documents_knowledge_vault"
contains "$TENANT_DIR/SOUL.md" 'business-data.md' "soul_documents_business_data_file"
contains "$TENANT_DIR/harness.yaml" '^tenant_harness_version:[[:space:]]*1' "manifest_has_harness_version"
contains "$TENANT_DIR/harness.yaml" '^verification_profile:' "manifest_has_verification_profile"
contains "$TENANT_DIR/harness.yaml" '^fixed_safety_profile:[[:space:]]*"?_fixed-safety-v1"?' "manifest_has_fixed_safety_profile"
# Spot-check that at least one platform rule's agent_instruction text actually
# landed inside the rendered BEGIN/END PLATFORM RULES block (not just that the
# markers exist). This is a representative phrase, not full per-rule coverage -
# the admin agent itself spot-checks every rule from platform-policy.yaml
# during onboarding/update per provision-tenant-vault's rendering instruction.
contains "$TENANT_DIR/SOUL.md" '[Nn]ever perform irreversible actions' "soul_has_fixed_safety_language"
exists_file "$PLATFORM_ROOT/tenant-hermes/evals/generated/$TENANT_ID-v1.yaml" "tenant_generated_eval_file"

if [ -f "$TENANT_DIR/skills/PROVENANCE.jsonl" ]; then
  record PASS "skills_provenance_present"
else
  record WARN "skills_provenance_present" "no self-written skills yet; expected for a freshly onboarded tenant"
fi
owned_by_hermes "$TENANT_DIR" "tenant_directory_owner_is_10000"
owned_by_hermes "$TENANT_DIR/harness.yaml" "tenant_harness_owner_is_10000"
owned_by_hermes "$TENANT_DIR/ACCEPTANCE.md" "tenant_acceptance_owner_is_10000"
owned_by_hermes "$TENANT_DIR/vault" "tenant_knowledge_vault_owner_is_10000"

if [ -f "$TENANT_DIR/.env" ] && grep -Eq '(sk-[A-Za-z0-9_-]{12,}|xox[baprs]-|[0-9]{8,}:[A-Za-z0-9_-]{20,})' "$TENANT_DIR/.env.template" 2>/dev/null; then
  record FAIL "env_template_has_secret_like_value" ".env.template must contain keys only"
else
  record PASS "env_template_has_no_obvious_secrets"
fi

# Ownership (chown -R 10000:10000) doesn't grant the host operator/automation
# user read access, and a one-time top-level chmod misses subdirectories the
# tenant container creates later at runtime (mnemosyne data, logs, etc.),
# which inherit the container's restrictive default umask. Check recursively,
# not just the top-level directory, or this regresses silently between runs.
if [ -d "$TENANT_DIR" ]; then
  unreadable="$(find "$TENANT_DIR" \( -type d -not -perm -005 \) -o \( -type f -not -perm -004 \) 2>/dev/null | head -5)"
  if [ -z "$unreadable" ]; then
    record PASS "tenant_volume_host_readable"
  else
    record FAIL "tenant_volume_host_readable" "not group/other-readable: $(echo "$unreadable" | tr '\n' ' ')"
  fi
else
  record WARN "tenant_volume_host_readable" "tenant dir not found: $TENANT_DIR"
fi

contains "$COMPOSE_FILE" "^  $SERVICE:" "compose_has_tenant_service"
service_contains "$SERVICE" "restart:[[:space:]]*unless-stopped" "compose_has_restart_policy"
service_contains "$SERVICE" "mem_limit:[[:space:]]*1g" "compose_has_memory_limit"
service_contains "$SERVICE" "cpus:[[:space:]]*[\"']?1[.]0[\"']?" "compose_has_cpu_limit"
contains "$COMPOSE_FILE" "$TENANT_DIR:/opt/data" "compose_mounts_tenant_data"
contains "$COMPOSE_FILE" "$TENANT_DIR/files:/home/hermes/files" "compose_mounts_tenant_files"
contains "$COMPOSE_FILE" "$TENANT_DIR/vault:/home/hermes/vault" "compose_mounts_tenant_vault"
contains "$COMPOSE_FILE" "$TENANT_DIR/.env" "compose_uses_tenant_env"
service_contains "$SERVICE" "hermes-${TENANT_ID}-net" "compose_uses_isolated_tenant_network"
# A tenant service left on the bare `gateway run` command (pre-0.15.0, or a
# missed step 8 during onboarding/upgrade) never runs reconcile-plugins.sh on
# container start, so tenant-installed plugins silently never get
# reconciled after a recreate even though tenant_scripts_present above
# passes — the scripts existing on disk proves nothing if they're never
# invoked. Check the wiring, not just the files.
service_contains "$SERVICE" "/opt/data/scripts/tenant-entrypoint.sh" "compose_uses_tenant_entrypoint"
# Healthcheck — required so docker inspect .State.Health.Status is meaningful
# for the watchdog; without it the watchdog can only see "running", not "stuck".
service_contains "$SERVICE" "pgrep -f 'gateway run'" "compose_has_healthcheck"
# Watchdog labels — required for aaas-watchdog.sh to pick up this tenant automatically.
service_contains "$SERVICE" "aaas\.watchdog:[[:space:]]*\"true\"" "compose_has_watchdog_label"
service_contains "$SERVICE" "aaas\.watchdog\.priority:[[:space:]]*\"5\"" "compose_has_watchdog_priority"
service_contains "$SERVICE" "aaas\.watchdog\.playbook:[[:space:]]*\"troubleshoot-tenant\.md\"" "compose_has_watchdog_playbook"
# External network declaration — required so Compose does not try to create a
# network it doesn't own, and so the explicit name: prevents project-prefixing.
contains "$COMPOSE_FILE" "hermes-${TENANT_ID}-net:" "compose_network_block_declared"
contains "$COMPOSE_FILE" "external:[[:space:]]*true" "compose_network_external_true"
contains "$TENANTS_FILE" "id:[[:space:]]*$TENANT_ID|tenant_id:[[:space:]]*$TENANT_ID|$TENANT_ID" "tenant_registry_mentions_tenant"

if command -v docker >/dev/null 2>&1; then
  if docker network inspect "hermes-${TENANT_ID}-net" >/dev/null 2>&1; then
    record PASS "tenant_isolated_network_exists" "hermes-${TENANT_ID}-net"
  else
    record FAIL "tenant_isolated_network_exists" "missing: hermes-${TENANT_ID}-net"
  fi

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

  # Static config/env checks above only prove the tenant's files *say* it
  # should use Mnemosyne; they don't prove the plugin is actually active in
  # the running container. A HERMES_HOME mismatch between the one-time
  # activation commands (onboard-tenant.md step 12) and the container's own
  # runtime env, or a recreate that dropped activation state, would pass
  # every check above while memory is silently non-functional. Check the
  # live provider directly.
  mnemosyne_status="$(docker exec "$SERVICE" sh -lc 'hermes memory status 2>/dev/null || hermes hermes-mnemosyne status 2>/dev/null' 2>/dev/null || true)"
  if echo "$mnemosyne_status" | grep -qi 'mnemosyne'; then
    record PASS "container_mnemosyne_active"
  else
    record WARN "container_mnemosyne_active" "hermes memory status did not report an active mnemosyne provider; container unavailable or plugin not activated - see mnemosyne-seed-corruption.md"
  fi

  if docker exec "$SERVICE" sh -lc 'curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org' 2>/dev/null | grep -Eq '^(200|301|302|404)$'; then
    record PASS "container_outbound_https"
  else
    record WARN "container_outbound_https" "Telegram API HTTPS check did not return expected code"
  fi

  # Proves isolation, not just network existence: Agent Vault's management
  # port must be unreachable from inside this tenant container. Agent Vault
  # itself is never joined to a tenant network — only a forwarding-only
  # sidecar (agent-vault-proxy-{tenant-id}) is, and that sidecar has no route
  # to :14321 to forward in the first place, so this should fail to resolve
  # or connect by construction, not because of an access-control rule that
  # could later be misconfigured. The proxy port (:14322), reached via the
  # sidecar hostname, is what tenants actually use and is checked separately.
  if docker exec "$SERVICE" sh -lc 'curl -s --connect-timeout 2 http://agent-vault:14321/health' >/dev/null 2>&1; then
    record FAIL "agent_vault_mgmt_port_not_reachable_from_tenant" "tenant container could reach :14321"
  else
    record PASS "agent_vault_mgmt_port_not_reachable_from_tenant"
  fi

  # The sidecar itself must also never expose :14321 — confirm only :14322 is
  # reachable from the tenant container via the sidecar hostname.
  if docker exec "$SERVICE" sh -lc "curl -s --connect-timeout 2 http://agent-vault-proxy-${TENANT_ID}:14321/health" >/dev/null 2>&1; then
    record FAIL "agent_vault_sidecar_mgmt_port_not_reachable" "tenant container could reach sidecar :14321"
  else
    record PASS "agent_vault_sidecar_mgmt_port_not_reachable"
  fi

  # The two checks above prove *unreachable*, which is also exactly what a
  # dead sidecar looks like — a crashed agent-vault-proxy-{tenant-id} gives
  # the same "connection refused" result as a properly locked-down one, so
  # both would silently PASS while the tenant's LLM calls are actually
  # broken. Prove liveness directly instead of inferring it from an absence.
  if docker ps --filter "name=^/agent-vault-proxy-${TENANT_ID}$" --format '{{.Names}}' 2>/dev/null | grep -qx "agent-vault-proxy-${TENANT_ID}"; then
    record PASS "agent_vault_sidecar_running" "agent-vault-proxy-${TENANT_ID}"
  else
    record FAIL "agent_vault_sidecar_running" "agent-vault-proxy-${TENANT_ID} not running"
  fi

  # Positive counterpart to the two not-reachable checks above: :14322 is the
  # port tenants actually use, so a real connection here is what proves the
  # sidecar is up and forwarding, rather than just absent from the network.
  # Any HTTP response code (including 407 for missing/invalid auth) counts as
  # reachable; only a connection failure (empty/000) means the sidecar or its
  # forwarding path is down.
  proxy_code="$(docker exec "$SERVICE" sh -lc "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 http://agent-vault-proxy-${TENANT_ID}:14322/" 2>/dev/null || true)"
  if [ -n "$proxy_code" ] && [ "$proxy_code" != "000" ]; then
    record PASS "agent_vault_sidecar_proxy_port_reachable" "http_code=$proxy_code"
  else
    record FAIL "agent_vault_sidecar_proxy_port_reachable" "no response from agent-vault-proxy-${TENANT_ID}:14322"
  fi
else
  record WARN "docker_available" "docker command not found; skipped runtime checks"
fi

echo ""
echo "summary pass=$PASS_COUNT warn=$WARN_COUNT fail=$FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]