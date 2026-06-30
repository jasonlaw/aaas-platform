#!/usr/bin/env bash
# Verify every rule in platform-policy.yaml has at least one corresponding
# check name present in _fixed-safety-v1.yaml.
#
# Run before platform upgrades and after editing platform-policy.yaml
# (generate-platform-eval.sh should already keep these in sync, but this
# script catches drift if _fixed-safety-v1.yaml was ever hand-edited or a
# generation step was skipped).
#
# Usage: ./validate-platform-rules.sh [policy-file] [eval-file]

set -euo pipefail

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
POLICY_FILE="${1:-$PLATFORM_ROOT/policy/platform-policy.yaml}"
EVAL_FILE="${2:-$PLATFORM_ROOT/tenant-hermes/evals/_fixed-safety-v1.yaml}"

ERRORS=0

fail() { printf 'FAIL\t%s\n' "$1"; ERRORS=$((ERRORS + 1)); }
pass() { printf 'PASS\t%s\n' "$1"; }

command -v yq >/dev/null 2>&1 || { echo "FAIL setup: yq is required" >&2; exit 2; }
[ -f "$POLICY_FILE" ] || { echo "FAIL setup: missing policy file: $POLICY_FILE" >&2; exit 2; }
[ -f "$EVAL_FILE" ] || { echo "FAIL setup: missing eval file: $EVAL_FILE" >&2; exit 2; }

echo "AaaS platform rule coverage validation"
echo "policy_file=$POLICY_FILE"
echo "eval_file=$EVAL_FILE"
echo ""

RULE_COUNT="$(yq '.rules | length' "$POLICY_FILE")"
EVAL_CHECK_NAMES="$(yq -r '.checks[].name' "$EVAL_FILE")"

i=0
while [ "$i" -lt "$RULE_COUNT" ]; do
  RULE_ID="$(yq -r ".rules[$i].id" "$POLICY_FILE")"
  CHECK_COUNT="$(yq ".rules[$i].eval_checks | length" "$POLICY_FILE")"

  if [ "$CHECK_COUNT" -eq 0 ]; then
    fail "rule_has_no_eval_checks:$RULE_ID"
    i=$((i + 1))
    continue
  fi

  covered=0
  j=0
  while [ "$j" -lt "$CHECK_COUNT" ]; do
    CHECK_NAME="$(yq -r ".rules[$i].eval_checks[$j].name" "$POLICY_FILE")"
    if printf '%s\n' "$EVAL_CHECK_NAMES" | grep -Fxq "$CHECK_NAME"; then
      covered=$((covered + 1))
    else
      fail "rule_check_missing_from_eval_file:$RULE_ID:$CHECK_NAME"
    fi
    j=$((j + 1))
  done

  if [ "$covered" -eq "$CHECK_COUNT" ]; then
    pass "rule_fully_covered:$RULE_ID"
  fi

  i=$((i + 1))
done

echo ""
echo "summary fail=$ERRORS"
[ "$ERRORS" -eq 0 ]
