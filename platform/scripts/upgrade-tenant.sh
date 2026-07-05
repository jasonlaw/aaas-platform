#!/usr/bin/env bash
# Run all per-tenant upgrade sub-steps idempotently and recreate the container
# only when something actually changed or the image is out of date.
#
# Replaces the long inline step 3 prose block in upgrade-tenants.md, which
# contained 8 distinct sub-steps with conditional logic the agent had to hold
# in context simultaneously for every active tenant.
#
# This script:
#   - runs all backfill sub-steps idempotently (no-op when already correct)
#   - tracks a NEEDS_RECREATE flag internally (not via prose reasoning)
#   - performs the image-ID comparison correctly (ID vs ID, not tag vs tag)
#   - prints RECREATED, SKIPPED, or FAIL per tenant so upgrade-tenants.md
#     can aggregate results without per-tenant reasoning
#
# Directly analogous to eval-runner.sh, which already encapsulates the
# per-tenant eval loop — same pattern applied to the upgrade loop.
#
# Usage:
#   upgrade-tenant.sh {tenant-id} {target-image-id}
#
#   {target-image-id} — the full image ID resolved once by upgrade-tenants.md
#                       step 2 via: docker inspect --format '{{.Id}}' hermes-tenant:latest
#
# Exit codes:
#   0 — RECREATED or SKIPPED (both are success outcomes)
#   1 — FAIL (pre-condition or sub-step error; upgrade-tenants.md should stop and report)
#
# Environment overrides (for testing):
#   PLATFORM_ROOT   (default: /opt/aaas/platform)
#   TENANT_ROOT     (default: /opt/aaas/tenants)

set -euo pipefail

TENANT_ID="${1:-}"
TARGET_IMAGE_ID="${2:-}"

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
SCRIPTS_DIR="$PLATFORM_ROOT/scripts"

usage() {
  echo "Usage: $0 {tenant-id} {target-image-id}" >&2
  echo "  target-image-id: output of: docker inspect --format '{{.Id}}' hermes-tenant:latest" >&2
}

fail() {
  echo "FAIL  [$TENANT_ID] $1" >&2
  exit 1
}

note() {
  echo "      [$TENANT_ID] $1"
}

changed() {
  # Call when a sub-step actually mutates a file, network, or compose entry.
  # Sets NEEDS_RECREATE=true and logs the reason.
  NEEDS_RECREATE=true
  note "change detected: $1 → will recreate"
}

# --- Argument validation ---

if [ -z "$TENANT_ID" ] || [[ "$TENANT_ID" == -* ]]; then
  usage
  fail "missing or invalid tenant-id"
fi

if [ -z "$TARGET_IMAGE_ID" ]; then
  usage
  fail "missing target-image-id"
fi

TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
TENANTS_YAML="$PLATFORM_ROOT/tenants.yaml"
COMPOSE_FILE="$PLATFORM_ROOT/docker/docker-compose.yaml"
HARNESS_TEMPLATE="$PLATFORM_ROOT/harness/tenant-harness.yaml.template"
ACCEPTANCE_TEMPLATE="$PLATFORM_ROOT/harness/ACCEPTANCE.md.template"
POLICY_TEMPLATE="$PLATFORM_ROOT/tenant-hermes/policy/tenant-policy.yaml.template"
SOUL_TEMPLATE="$PLATFORM_ROOT/tenant-hermes/SOUL.md.template"
PLATFORM_POLICY="$PLATFORM_ROOT/policy/platform-policy.yaml"

[ -d "$TENANT_DIR" ] \
  || fail "tenant directory not found: $TENANT_DIR"

NEEDS_RECREATE=false

# --- Sub-step: ensure harness.yaml exists ---

HARNESS_FILE="$TENANT_DIR/harness.yaml"
if [ ! -f "$HARNESS_FILE" ]; then
  if [ -f "$HARNESS_TEMPLATE" ]; then
    # Fill in known fields; mark unknowns clearly
    sed "s/{{TENANT_ID}}/$TENANT_ID/g" "$HARNESS_TEMPLATE" > "$HARNESS_FILE"
    note "created harness.yaml from template (unknown fields marked)"
  else
    # Minimal stub so downstream checks don't hard-fail on a missing file
    printf 'tenant_id: %s\nstatus: unknown\n' "$TENANT_ID" > "$HARNESS_FILE"
    note "created minimal harness.yaml stub (template not found)"
  fi
  changed "harness.yaml created"
fi

# --- Sub-step: ensure ACCEPTANCE.md exists ---

ACCEPTANCE_FILE="$TENANT_DIR/ACCEPTANCE.md"
if [ ! -f "$ACCEPTANCE_FILE" ]; then
  if [ -f "$ACCEPTANCE_TEMPLATE" ]; then
    sed "s/{{TENANT_ID}}/$TENANT_ID/g" "$ACCEPTANCE_TEMPLATE" > "$ACCEPTANCE_FILE"
  else
    printf '# Acceptance — %s\n\n(Created by upgrade-tenant.sh; fill in after next eval run.)\n' "$TENANT_ID" > "$ACCEPTANCE_FILE"
  fi
  note "created ACCEPTANCE.md"
  changed "ACCEPTANCE.md created"
fi

# --- Sub-step: backfill knowledge vault if missing ---
# Requires business name; read it from tenants.yaml if available.

VAULT_DIR="$TENANT_DIR/vault"
if [ ! -d "$VAULT_DIR" ]; then
  BUSINESS_NAME=""
  if [ -f "$TENANTS_YAML" ]; then
    # Simple grep-based extraction — tenants.yaml uses business_name: "..." convention
    BUSINESS_NAME="$(grep -A 5 "id: ${TENANT_ID}" "$TENANTS_YAML" | grep "business_name:" | head -1 | sed 's/.*business_name:[[:space:]]*//' | tr -d '"' || true)"
  fi
  BUSINESS_NAME="${BUSINESS_NAME:-$TENANT_ID}"

  if [ -f "$SCRIPTS_DIR/backfill-tenant-vault.sh" ]; then
    "$SCRIPTS_DIR/backfill-tenant-vault.sh" "$TENANT_ID" "$BUSINESS_NAME" \
      || fail "backfill-tenant-vault.sh failed"
    changed "knowledge vault backfilled"
  else
    note "WARN backfill-tenant-vault.sh not found — skipping vault backfill"
  fi
fi

# --- Sub-step: ensure tenant-policy.yaml exists ---

POLICY_FILE="$TENANT_DIR/tenant-policy.yaml"
if [ ! -f "$POLICY_FILE" ]; then
  if [ -f "$POLICY_TEMPLATE" ]; then
    sed -e "s/{{TENANT_ID}}/$TENANT_ID/g" -e "s/{{BUSINESS_NAME}}/$TENANT_ID/g" \
      "$POLICY_TEMPLATE" > "$POLICY_FILE"
  else
    printf 'tenant_id: %s\nrules: []\n' "$TENANT_ID" > "$POLICY_FILE"
  fi
  note "created tenant-policy.yaml"
  changed "tenant-policy.yaml created"
fi

# --- Sub-step: install/update tenant runtime scripts ---

if [ -f "$SCRIPTS_DIR/install-tenant-scripts.sh" ]; then
  # Capture output to detect if any script was actually installed (not just skipped)
  INSTALL_OUT="$("$SCRIPTS_DIR/install-tenant-scripts.sh" "$TENANT_ID" 2>&1)"
  echo "$INSTALL_OUT" | while IFS= read -r line; do note "$line"; done
  if echo "$INSTALL_OUT" | grep -q "^PASS.*installed$"; then
    changed "runtime scripts updated"
  fi
else
  note "WARN install-tenant-scripts.sh not found — skipping runtime script install"
fi

# --- Sub-step: ensure isolated network and forwarding sidecar ---

NETWORK_NAME="hermes-${TENANT_ID}-net"
SIDECAR_NAME="agent-vault-proxy-${TENANT_ID}"

if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  docker network create "${NETWORK_NAME}"
  note "created isolated network ${NETWORK_NAME}"
  changed "network created"
fi

if ! docker ps -a --format '{{.Names}}' | grep -qx "${SIDECAR_NAME}"; then
  docker run -d \
    --name "${SIDECAR_NAME}" \
    --restart unless-stopped \
    --network agent-vault-net \
    alpine/socat \
    TCP-LISTEN:14322,fork,reuseaddr TCP:agent-vault:14322
  note "started sidecar ${SIDECAR_NAME}"
  changed "sidecar started"
fi

docker network connect "${NETWORK_NAME}" "${SIDECAR_NAME}" 2>/dev/null || true
# Drop Agent Vault's own direct connection (pre-isolation tenants only)
docker network disconnect "${NETWORK_NAME}" agent-vault 2>/dev/null || true

# Check compose uses per-tenant network (not old shared agent-vault-net)
if grep -A 20 "hermes_${TENANT_ID}:" "$COMPOSE_FILE" 2>/dev/null \
    | grep -q "agent-vault-net" && \
   ! grep -A 20 "hermes_${TENANT_ID}:" "$COMPOSE_FILE" 2>/dev/null \
    | grep -q "${NETWORK_NAME}"; then
  note "WARN compose service still references agent-vault-net — update network to ${NETWORK_NAME} and HTTP_PROXY/HTTPS_PROXY in .env manually"
  changed "network reference in compose needs update (flagged)"
fi

# --- Sub-step: repair ownership ---

if [ -f "$SCRIPTS_DIR/repair-tenant-ownership.sh" ]; then
  "$SCRIPTS_DIR/repair-tenant-ownership.sh" "$TENANT_ID" \
    | while IFS= read -r line; do note "$line"; done
else
  sudo chown -R 10000:10000 "$TENANT_DIR"
  sudo chmod -R go+rX "$TENANT_DIR"
  note "ownership repaired"
fi

# --- Sub-step: re-render SOUL.md policy blocks ---
# SOUL.md is intentionally re-rendered on every upgrade so platform and tenant
# policy changes are picked up automatically. Only the two marker-delimited
# policy blocks are updated; all other SOUL.md content (capabilities block,
# brand tone, conduct lines) is left exactly as-is.
#
# MEMORY.md and USER.md are intentionally NOT touched here — they are
# maintained at runtime by the tenant agent (Mnemosyne) and must not be
# overwritten by the upgrade process. Any runtime-accumulated facts or
# preferences would be lost if these files were regenerated from templates.

SOUL_FILE="$TENANT_DIR/SOUL.md"
TENANT_POLICY_FILE="$TENANT_DIR/tenant-policy.yaml"

if [ -f "$SOUL_FILE" ]; then
  # Render platform rules from platform-policy.yaml
  PLATFORM_RULES_BLOCK=""
  if [ -f "$PLATFORM_POLICY" ]; then
    # Extract agent_instruction lines from each rule block and render as bullets.
    # Uses awk to collect multi-line agent_instruction values under each rule entry.
    PLATFORM_RULES_BLOCK="$(awk '
      /^  - id:/ { in_rule=1; buf="" }
      in_rule && /agent_instruction:/ {
        # inline value on same line (agent_instruction: "text")
        sub(/.*agent_instruction:[[:space:]]*>?[[:space:]]*/, ""); gsub(/^"|"$/, "")
        if (length($0) > 0) { buf = $0; next }
        in_instr=1; buf=""; next
      }
      in_rule && in_instr {
        # multi-line block scalar — stop on dedent (next key at same indent)
        if (/^  [a-z_]+:/) { in_instr=0; print "- " buf; buf=""; next }
        sub(/^[[:space:]]{4,6}/, ""); buf = (buf=="" ? $0 : buf " " $0)
      }
      !in_instr && in_rule && buf != "" { print "- " buf; buf=""; in_rule=0 }
    END { if (buf != "") print "- " buf }
    ' "$PLATFORM_POLICY")"
  fi

  # Render tenant rules from tenant-policy.yaml
  TENANT_RULES_BLOCK=""
  if [ -f "$TENANT_POLICY_FILE" ]; then
    TENANT_RULES_BLOCK="$(awk '
      /^  - id:/ { in_rule=1; buf="" }
      in_rule && /agent_instruction:/ {
        sub(/.*agent_instruction:[[:space:]]*>?[[:space:]]*/, ""); gsub(/^"|"$/, "")
        if (length($0) > 0) { buf = $0; next }
        in_instr=1; buf=""; next
      }
      in_rule && in_instr {
        if (/^  [a-z_]+:/) { in_instr=0; print "- " buf; buf=""; next }
        sub(/^[[:space:]]{4,6}/, ""); buf = (buf=="" ? $0 : buf " " $0)
      }
      !in_instr && in_rule && buf != "" { print "- " buf; buf=""; in_rule=0 }
    END { if (buf != "") print "- " buf }
    ' "$TENANT_POLICY_FILE")"
  fi

  # Rewrite only the content between the BEGIN/END marker comment pairs.
  # sed reads the file; between each pair of markers it replaces any
  # existing bullet lines with the freshly-rendered block, then resumes
  # normal output. Lines outside the markers are passed through unchanged.
  SOUL_UPDATED="$(awk -v plat="$PLATFORM_RULES_BLOCK" -v tenant="$TENANT_RULES_BLOCK" '
    /<!-- BEGIN PLATFORM RULES/ { print; in_plat=1; next }
    /<!-- END PLATFORM RULES/   {
      if (plat != "") print plat
      in_plat=0; print; next
    }
    /<!-- BEGIN TENANT RULES/   { print; in_tenant=1; next }
    /<!-- END TENANT RULES/     {
      if (tenant != "") print tenant
      in_tenant=0; print; next
    }
    in_plat || in_tenant { next }   # drop old rendered lines between markers
    { print }
  ' "$SOUL_FILE")"

  # Only write if content actually changed (avoids spurious NEEDS_RECREATE)
  SOUL_CURRENT="$(cat "$SOUL_FILE")"
  if [ "$SOUL_UPDATED" != "$SOUL_CURRENT" ]; then
    printf '%s\n' "$SOUL_UPDATED" > "$SOUL_FILE"
    note "SOUL.md policy blocks re-rendered (volume-mounted — no recreate needed; takes effect on next container restart)"
  else
    note "SOUL.md policy blocks unchanged — skipping"
  fi
else
  note "WARN SOUL.md not found at $SOUL_FILE — skipping policy block re-render"
fi

# --- Sub-step: validate config ---

if [ -f "$SCRIPTS_DIR/validate-tenant-config.sh" ]; then
  "$SCRIPTS_DIR/validate-tenant-config.sh" "$TENANT_ID" \
    | while IFS= read -r line; do note "$line"; done
else
  note "WARN validate-tenant-config.sh not found — skipping config validation"
fi

# --- Decide: recreate or skip ---

CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "hermes_${TENANT_ID}" 2>/dev/null || echo "missing")"

if [ "$CURRENT_IMAGE_ID" != "$TARGET_IMAGE_ID" ]; then
  note "image differs (running: ${CURRENT_IMAGE_ID:0:20}... target: ${TARGET_IMAGE_ID:0:20}...) → will recreate"
  NEEDS_RECREATE=true
fi

if [ "$NEEDS_RECREATE" = "true" ]; then
  docker compose -f "$COMPOSE_FILE" up --force-recreate --no-deps -d "hermes_${TENANT_ID}"
  note "container recreated"
  docker ps --filter "name=hermes_${TENANT_ID}" --format "{{.Status}}" | head -1 | while IFS= read -r line; do note "status: $line"; done
else
  note "image matches and no backfill changes — container up to date"
fi

# --- Harness check ---

if [ -f "$PLATFORM_ROOT/harness/check-tenant.sh" ]; then
  "$PLATFORM_ROOT/harness/check-tenant.sh" "$TENANT_ID" \
    | while IFS= read -r line; do note "$line"; done
fi

# --- Update tenants.yaml ---

if [ -f "$TENANTS_YAML" ]; then
  TODAY="$(date -u +%Y-%m-%d)"
  sed -i "s/last_updated:.*/last_updated: $TODAY/" "$TENANTS_YAML" 2>/dev/null || true
fi

# --- Final result ---

if [ "$NEEDS_RECREATE" = "true" ]; then
  echo "RECREATED [$TENANT_ID]"
else
  echo "SKIPPED [$TENANT_ID] no changes"
fi
