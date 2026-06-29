#!/usr/bin/env bash
# Generate platform/evals/tenant-agent/_fixed-safety-v1.yaml from
# platform/policy/platform-policy.yaml.
#
# _fixed-safety-v1.yaml is no longer hand-authored. Run this after editing
# platform-policy.yaml, and as part of upgrade-platform.md. Hand-edits to
# _fixed-safety-v1.yaml are overwritten the next time this script runs.
#
# Output format is unchanged from the existing hand-authored file and stays
# compatible with eval-runner.sh / _eval-check-single.sh / eval-judge.sh:
#   eval_profile, version, purpose, run_mode, checks[] where each check has
#   name, match_type, prompt, and either expected.must_include/must_not_include
#   (match_type: literal) or judge_for (match_type: semantic).
#
# Usage: ./generate-platform-eval.sh [policy-file] [output-file]

set -euo pipefail

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
POLICY_FILE="${1:-$PLATFORM_ROOT/policy/platform-policy.yaml}"
OUTPUT_FILE="${2:-$PLATFORM_ROOT/evals/tenant-agent/_fixed-safety-v1.yaml}"

command -v yq >/dev/null 2>&1 || { echo "FAIL setup: yq is required" >&2; exit 2; }
[ -f "$POLICY_FILE" ] || { echo "FAIL setup: missing policy file: $POLICY_FILE" >&2; exit 2; }

RULE_COUNT="$(yq '.rules | length' "$POLICY_FILE")"
[ "$RULE_COUNT" -gt 0 ] || { echo "FAIL setup: no rules in $POLICY_FILE" >&2; exit 2; }

# Bump this whenever the generated check set changes shape, independent of
# how many platform-policy.yaml rules exist.
EVAL_VERSION=3

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

{
  echo "eval_profile: fixed-safety-v1"
  echo "version: $EVAL_VERSION"
  echo "purpose: \"Vertical-agnostic safety and isolation checks. Identical for every tenant regardless of business type. Generated from platform/policy/platform-policy.yaml by generate-platform-eval.sh - do not hand-edit, do not generate or edit this file per-tenant.\""
  echo "run_mode: \"automated literal checks via eval-runner.sh for match_type: literal checks; operator-assisted Telegram/transcript review required for match_type: semantic checks\""
  echo "checks:"
} > "$TMP_FILE"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

i=0
while [ "$i" -lt "$RULE_COUNT" ]; do
  CHECK_COUNT="$(yq ".rules[$i].eval_checks | length" "$POLICY_FILE")"
  j=0
  while [ "$j" -lt "$CHECK_COUNT" ]; do
    NAME="$(yq -r ".rules[$i].eval_checks[$j].name" "$POLICY_FILE")"
    TYPE="$(yq -r ".rules[$i].eval_checks[$j].type" "$POLICY_FILE")"
    PROMPT_RAW="$(yq -r ".rules[$i].eval_checks[$j].prompt" "$POLICY_FILE")"
    PROMPT_RAW="${PROMPT_RAW%$'\n'}"

    {
      echo "  - name: $NAME"
      echo "    match_type: $TYPE"
      printf '    prompt: "%s"\n' "$(json_escape "$PROMPT_RAW")"
    } >> "$TMP_FILE"

    if [ "$TYPE" = "literal" ]; then
      echo "    expected:" >> "$TMP_FILE"
      MUST_INCLUDE_COUNT="$(yq ".rules[$i].eval_checks[$j].must_include | length" "$POLICY_FILE" 2>/dev/null || echo 0)"
      if [ "$MUST_INCLUDE_COUNT" -gt 0 ]; then
        echo "      must_include:" >> "$TMP_FILE"
        k=0
        while [ "$k" -lt "$MUST_INCLUDE_COUNT" ]; do
          TERM="$(yq -r ".rules[$i].eval_checks[$j].must_include[$k]" "$POLICY_FILE")"
          printf '        - "%s"\n' "$(json_escape "$TERM")" >> "$TMP_FILE"
          k=$((k + 1))
        done
      fi
      MUST_NOT_INCLUDE_COUNT="$(yq ".rules[$i].eval_checks[$j].must_not_include | length" "$POLICY_FILE" 2>/dev/null || echo 0)"
      if [ "$MUST_NOT_INCLUDE_COUNT" -gt 0 ]; then
        echo "      must_not_include:" >> "$TMP_FILE"
        k=0
        while [ "$k" -lt "$MUST_NOT_INCLUDE_COUNT" ]; do
          TERM="$(yq -r ".rules[$i].eval_checks[$j].must_not_include[$k]" "$POLICY_FILE")"
          printf '        - "%s"\n' "$(json_escape "$TERM")" >> "$TMP_FILE"
          k=$((k + 1))
        done
      fi
    elif [ "$TYPE" = "semantic" ]; then
      JUDGE_FOR_RAW="$(yq -r ".rules[$i].eval_checks[$j].judge_for" "$POLICY_FILE")"
      # platform-policy.yaml uses YAML folded block scalars (>) for judge_for,
      # which carry a trailing newline; strip it so the rendered string here
      # matches the tidy single-line style of the rest of this file.
      JUDGE_FOR_RAW="${JUDGE_FOR_RAW%$'\n'}"
      printf '    judge_for: "%s"\n' "$(json_escape "$JUDGE_FOR_RAW")" >> "$TMP_FILE"
    else
      echo "FAIL setup: unknown eval_checks type '$TYPE' for check '$NAME' (rule index $i, check index $j)" >&2
      exit 2
    fi

    j=$((j + 1))
  done
  i=$((i + 1))
done

# Validate the generated file is well-formed YAML before replacing the target.
yq '.' "$TMP_FILE" >/dev/null

mkdir -p "$(dirname "$OUTPUT_FILE")"
cp "$TMP_FILE" "$OUTPUT_FILE"
echo "PASS generated: $OUTPUT_FILE (from $RULE_COUNT platform-policy.yaml rules)"
