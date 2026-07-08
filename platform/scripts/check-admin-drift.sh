#!/usr/bin/env bash
# Detects admin Hermes SOUL.md/config.yaml drift from the shipped templates.
#
# Why this exists: unlike tenant SOUL.md/config.yaml (re-rendered every
# upgrade) or AGENTS.md/ADMIN-CONTEXT.md (overwritten wholesale every
# upgrade), platform/skills/setup-admin-hermes.md Step 2 copies
# admin-hermes/{SOUL.md,config.yaml}.template into /opt/aaas/platform/admin/
# exactly once, and nothing else in this repo ever touches those two files
# again. That has already caused a real regression: config.yaml.template
# gained a Telegram gateway block in 0.13.1 and a comment fix in 0.13.2, and
# any admin instance set up before either release silently kept the stale
# file with nothing flagging it (see upgrade-platform.md step 9.3, and
# setup-admin-hermes.md's own manual validation section, which this script
# automates rather than replaces).
#
# This does NOT flag every textual difference as a problem: config.yaml is
# filled in per-operator (fallback_providers, Telegram gateway block), so a
# raw `diff` against the template is expected to differ and is not itself
# a failure — see upgrade-platform.md step 9.3 for that manual diff step,
# which remains the right tool for reviewing intentional customization.
# What this script checks instead is the same fixed set of load-bearing
# content assertions setup-admin-hermes.md already tells an operator to grep
# for by hand (task-report rule, credential/secret rules, mnemosyne memory
# provider, native memory disabled) — the specific properties a stale file
# can silently lose after a template update. Extend PLATFORM assertions
# below if a future template change introduces another load-bearing line
# worth guarding.
#
# Exit status: 0 if nothing failed (WARNs and a missing admin install are
# not failures — admin Hermes may simply not be set up on this host yet).
# Intended to be run from preflight-check.sh and safe to run standalone:
#   ./check-admin-drift.sh

set -uo pipefail  # no -e: every check must run so one failure doesn't hide the rest

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
ADMIN_DIR="${PLATFORM_ROOT}/admin"
TEMPLATE_DIR="${PLATFORM_ROOT}/admin-hermes"

ADMIN_SOUL="${ADMIN_DIR}/SOUL.md"
ADMIN_CONFIG="${ADMIN_DIR}/config.yaml"
SOUL_TEMPLATE="${TEMPLATE_DIR}/SOUL.md.template"
CONFIG_TEMPLATE="${TEMPLATE_DIR}/config.yaml.template"

ERRORS=0
WARNINGS=0

pass() { printf 'PASS\t%s\n' "$1"; }
warn() { printf 'WARN\t%s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL\t%s\n' "$1"; ERRORS=$((ERRORS + 1)); }

echo "Admin Hermes config drift check"
echo "admin_dir=${ADMIN_DIR}"
echo ""

if [ ! -f "$ADMIN_SOUL" ]; then
  echo "SKIP: ${ADMIN_SOUL} does not exist — admin Hermes not yet set up on this host."
  exit 0
fi

# --- Existence of the templates we're comparing against ---
[ -f "$SOUL_TEMPLATE" ]   || { fail "missing_soul_template:${SOUL_TEMPLATE}"; }
[ -f "$CONFIG_TEMPLATE" ] || { fail "missing_config_template:${CONFIG_TEMPLATE}"; }

# --- Cheap signal: is there ANY difference at all? Not itself a failure —
# fallback_providers/Telegram blocks are legitimate per-operator content —
# but worth surfacing so an operator knows to run the manual `diff -u`
# from upgrade-platform.md step 9.3 and eyeball what changed. ---
if [ -f "$SOUL_TEMPLATE" ] && ! diff -q "$ADMIN_SOUL" "$SOUL_TEMPLATE" >/dev/null 2>&1; then
  warn "soul_md_differs_from_template:run 'diff -u ${ADMIN_SOUL} ${SOUL_TEMPLATE}' to review"
fi
if [ -f "$CONFIG_TEMPLATE" ] && ! diff -q "$ADMIN_CONFIG" "$CONFIG_TEMPLATE" >/dev/null 2>&1; then
  warn "config_yaml_differs_from_template:run 'diff -u ${ADMIN_CONFIG} ${CONFIG_TEMPLATE}' to review"
fi

# --- Load-bearing content assertions (mirrors setup-admin-hermes.md's
# manual validation section) — these ARE failures, since losing any of
# them is a real regression, not an expected per-operator customization. ---
if [ -f "$ADMIN_SOUL" ]; then
  grep -q "Always write a task report" "$ADMIN_SOUL" \
    && pass "soul_md_has_task_report_rule" \
    || fail "soul_md_missing_task_report_rule:re-copy or merge ${SOUL_TEMPLATE}"

  grep -q "Agent Vault is for LLM API keys only" "$ADMIN_SOUL" \
    && pass "soul_md_has_credential_rules" \
    || fail "soul_md_missing_credential_rules:re-copy or merge ${SOUL_TEMPLATE}"
fi

if [ -f "$ADMIN_CONFIG" ]; then
  grep -q "provider: mnemosyne" "$ADMIN_CONFIG" \
    && pass "config_yaml_uses_mnemosyne" \
    || fail "config_yaml_missing_mnemosyne_provider:re-copy or merge ${CONFIG_TEMPLATE}"

  grep -q "memory_enabled: false" "$ADMIN_CONFIG" \
    && pass "config_yaml_disables_native_memory" \
    || fail "config_yaml_native_memory_not_disabled:re-copy or merge ${CONFIG_TEMPLATE}"
fi

echo ""
echo "summary warn=${WARNINGS} fail=${ERRORS}"
[ "$ERRORS" -eq 0 ]
