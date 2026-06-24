#!/usr/bin/env bash
# Verify one self-written tenant skill and update its provenance ledger.

set -euo pipefail

TENANT_ID="${1:-}"
SKILL_NAME="${2:-}"
SPEC_FILE="${3:-}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"
PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
PROVENANCE_DIR="$TENANT_DIR/skills"
PROVENANCE_FILE="$PROVENANCE_DIR/PROVENANCE.jsonl"
LOCK_FILE="$PROVENANCE_DIR/PROVENANCE.lock"
EVAL_JUDGE="$PLATFORM_ROOT/scripts/eval-judge.sh"
ADMIN_ENV="$PLATFORM_ROOT/admin/.env"
ADMIN_HERMES="$PLATFORM_ROOT/admin/hermes"

usage() {
  echo "Usage: $0 {tenant-id} {skill-name} {verification-spec-yaml-or-json}"
}

record() {
  local status="$1"
  local check="$2"
  local detail="${3:-}"
  if [ -n "$detail" ]; then
    printf '%s\t%s\t%s\n' "$status" "$check" "$detail"
  else
    printf '%s\t%s\n' "$status" "$check"
  fi
}

require_setup() {
  if [ -z "$TENANT_ID" ] || [ -z "$SKILL_NAME" ] || [ -z "$SPEC_FILE" ]; then
    usage
    exit 2
  fi
  command -v yq >/dev/null 2>&1 || { record FAIL setup "yq is required"; exit 2; }
  command -v jq >/dev/null 2>&1 || { record FAIL setup "jq is required"; exit 2; }
  command -v flock >/dev/null 2>&1 || { record FAIL setup "flock is required"; exit 2; }
  [ -d "$TENANT_DIR" ] || { record FAIL setup "missing tenant directory: $TENANT_DIR"; exit 2; }
  [ -f "$SPEC_FILE" ] || { record FAIL setup "missing verification spec: $SPEC_FILE"; exit 2; }
  mkdir -p "$PROVENANCE_DIR"
  touch "$PROVENANCE_FILE"
}

spec_value() {
  local expr="$1"
  yq -r "$expr // \"\"" "$SPEC_FILE"
}

host_path_pattern() {
  local raw="$1"
  case "$raw" in
    ~/*) printf '%s/files/%s' "$TENANT_DIR" "${raw#~/files/}" ;;
    /home/hermes/files/*) printf '%s/files/%s' "$TENANT_DIR" "${raw#/home/hermes/files/}" ;;
    /opt/data/*) printf '%s/%s' "$TENANT_DIR" "${raw#/opt/data/}" ;;
    /*) printf '%s' "$raw" ;;
    *) printf '%s/%s' "$TENANT_DIR" "$raw" ;;
  esac
}

check_file_exists_at() {
  local pattern host_pattern
  pattern="$(spec_value '.params.path_pattern')"
  [ -n "$pattern" ] || { record FAIL file_exists_at "missing params.path_pattern"; return 1; }
  host_pattern="$(host_path_pattern "$pattern")"
  if compgen -G "$host_pattern" >/dev/null; then
    record PASS file_exists_at "$pattern"
    return 0
  fi
  record FAIL file_exists_at "no match: $pattern"
  return 1
}

check_file_does_not_exist_at() {
  local pattern host_pattern
  pattern="$(spec_value '.params.path_pattern')"
  [ -n "$pattern" ] || { record FAIL file_does_not_exist_at "missing params.path_pattern"; return 1; }
  host_pattern="$(host_path_pattern "$pattern")"
  if compgen -G "$host_pattern" >/dev/null; then
    record FAIL file_does_not_exist_at "unexpected match: $pattern"
    return 1
  fi
  record PASS file_does_not_exist_at "$pattern"
  return 0
}

check_content_includes() {
  local target must_include host_target
  target="$(spec_value '.params.target')"
  must_include="$(spec_value '.params.must_include')"
  [ -n "$target" ] || { record FAIL content_includes "missing params.target"; return 1; }
  [ -n "$must_include" ] || { record FAIL content_includes "missing params.must_include"; return 1; }
  host_target="$(host_path_pattern "$target")"
  if [ -f "$host_target" ]; then
    if grep -Fq "$must_include" "$host_target"; then
      record PASS content_includes "$target includes required text"
      return 0
    fi
    record FAIL content_includes "$target missing required text"
    return 1
  fi
  case "$target" in
    *"$must_include"*) record PASS content_includes "target text includes required text"; return 0 ;;
    *) record FAIL content_includes "target file missing or text did not include required text"; return 1 ;;
  esac
}

check_no_error_thrown() {
  local exit_code
  exit_code="$(spec_value '.params.exit_code')"
  if [ -z "$exit_code" ] || [ "$exit_code" = "0" ]; then
    record PASS no_error_thrown "skill run completed without a recorded error"
    return 0
  fi
  record FAIL no_error_thrown "recorded exit_code=$exit_code"
  return 1
}

check_confirmation_sent_before() {
  local action confirmed
  action="$(spec_value '.params.action_description')"
  confirmed="$(spec_value '.params.confirmed')"
  if [ "$confirmed" = "true" ] || [ "$confirmed" = "1" ]; then
    record PASS confirmation_sent_before "${action:-irreversible action}"
    return 0
  fi
  record FAIL confirmation_sent_before "missing positive confirmation evidence for: ${action:-irreversible action}"
  return 1
}

run_judge_fallback() {
  local prompt reply judge_for
  judge_for="$(spec_value '.judge_for')"
  prompt="$(spec_value '.prompt')"
  reply="$(spec_value '.reply')"
  [ -n "$prompt" ] || prompt="Verify skill: $SKILL_NAME"
  [ -n "$reply" ] || reply="${SKILL_VERIFY_REPLY:-}"
  if [ ! -f "$ADMIN_ENV" ] || [ ! -x "$ADMIN_HERMES" ]; then
    record WARN judge "verification=unavailable; optional admin dashboard prerequisites missing"
    update_provenance "provisional" "unavailable" 0
    return 0
  fi
  [ -n "$judge_for" ] || { record FAIL judge "missing judge_for"; update_provenance "flagged" "judge" 1; return 1; }
  [ -n "$reply" ] || { record FAIL judge "missing reply text to grade"; update_provenance "flagged" "judge" 1; return 1; }
  if "$EVAL_JUDGE" "skill_${SKILL_NAME}" "$prompt" "$reply" "$judge_for"; then
    update_provenance "provisional" "judge" 0
    return 0
  fi
  update_provenance "flagged" "judge" 1
  return 1
}

update_provenance() {
  local forced_status="$1"
  local verification_result="$2"
  local failed="$3"
  local now tmp
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$PROVENANCE_FILE.tmp.$$"

  (
    flock 9
    jq -s -c \
      --arg skill "$SKILL_NAME" \
      --arg now "$now" \
      --argjson verification "$(yq -o=json '.' "$SPEC_FILE")" \
      --arg forced_status "$forced_status" \
      --arg verification_result "$verification_result" \
      --argjson failed "$failed" '
        def base:
          {skill: $skill, created_at: $now, triggering_task: "", verification: $verification,
           status: "provisional", pass_count: 0, fail_count: 0};
        def updated($old):
          ($old // base) as $r
          | ($r.pass_count // 0) as $passes
          | ($r.fail_count // 0) as $fails
          | if $failed == 1 then
              $r + {verification: $verification, status: "flagged", fail_count: ($fails + 1), last_failure_at: $now, last_checked_at: $now, last_result: "FAIL", last_verification: $verification_result}
            else
              ($passes + 1) as $new_passes
              | $r + {verification: $verification, pass_count: $new_passes, last_checked_at: $now, last_result: "PASS", last_verification: $verification_result}
              | .status = (if $forced_status == "provisional" or $verification.type == "judge" then "provisional" elif $new_passes >= 3 then "trusted" else "provisional" end)
            end;
        . as $rows
        | (map(select(.skill == $skill)) | last) as $current
        | (map(select(.skill != $skill)) + [updated($current)])[]
      ' "$PROVENANCE_FILE" > "$tmp"
    mv "$tmp" "$PROVENANCE_FILE"
  ) 9>"$LOCK_FILE"
}

require_setup
TYPE="$(spec_value '.type')"
[ -n "$TYPE" ] || { record FAIL setup "verification spec missing type"; exit 2; }

case "$TYPE" in
  file_exists_at)
    if check_file_exists_at; then update_provenance "" "$TYPE" 0; else update_provenance "flagged" "$TYPE" 1; exit 1; fi ;;
  file_does_not_exist_at)
    if check_file_does_not_exist_at; then update_provenance "" "$TYPE" 0; else update_provenance "flagged" "$TYPE" 1; exit 1; fi ;;
  content_includes)
    if check_content_includes; then update_provenance "" "$TYPE" 0; else update_provenance "flagged" "$TYPE" 1; exit 1; fi ;;
  no_error_thrown)
    if check_no_error_thrown; then update_provenance "" "$TYPE" 0; else update_provenance "flagged" "$TYPE" 1; exit 1; fi ;;
  confirmation_sent_before)
    if check_confirmation_sent_before; then update_provenance "" "$TYPE" 0; else update_provenance "flagged" "$TYPE" 1; exit 1; fi ;;
  judge)
    run_judge_fallback ;;
  *)
    record FAIL setup "unknown verification primitive: $TYPE"
    exit 2 ;;
esac
