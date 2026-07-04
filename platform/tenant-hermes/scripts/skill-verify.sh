#!/usr/bin/env bash
# Verify one self-written tenant skill and update its provenance ledger.
# Runs inside the tenant container by default, using /opt/data and
# /home/hermes/files. It intentionally avoids host-only dependencies.

set -euo pipefail

TENANT_ID="${1:-}"
SKILL_NAME="${2:-}"
SPEC_FILE="${3:-}"
TRIGGERING_TASK="${4:-}"
TENANT_ROOT="${TENANT_ROOT:-/opt/aaas/tenants}"

if [ -n "${TENANT_DIR:-}" ]; then
  TENANT_DIR="$TENANT_DIR"
elif [ -d /opt/data ]; then
  TENANT_DIR="/opt/data"
else
  TENANT_DIR="$TENANT_ROOT/$TENANT_ID"
fi

if [ -n "${FILES_DIR:-}" ]; then
  FILES_DIR="$FILES_DIR"
elif [ -d /home/hermes/files ]; then
  FILES_DIR="/home/hermes/files"
else
  FILES_DIR="$TENANT_DIR/files"
fi

PROVENANCE_DIR="$TENANT_DIR/skills"
PROVENANCE_FILE="$PROVENANCE_DIR/PROVENANCE.jsonl"
LOCK_DIR="$PROVENANCE_DIR/PROVENANCE.lockdir"

usage() {
  echo "Usage: $0 {tenant-id} {skill-name} {verification-spec-yaml} [triggering-task]"
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

strip_value() {
  local value="$1"
  value="${value%%#*}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

spec_top_value() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ "^" key ":[[:space:]]*" {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }
  ' "$SPEC_FILE" | while IFS= read -r value; do strip_value "$value"; done
}

spec_param_value() {
  local key="$1"
  awk -v key="$key" '
    /^params:[[:space:]]*$/ { in_params=1; next }
    in_params && /^[^[:space:]]/ { in_params=0 }
    in_params && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      print
      exit
    }
  ' "$SPEC_FILE" | while IFS= read -r value; do strip_value "$value"; done
}

spec_value() {
  local expr="$1"
  case "$expr" in
    .type) spec_top_value "type" ;;
    .judge_for) spec_top_value "judge_for" ;;
    .prompt) spec_top_value "prompt" ;;
    .reply) spec_top_value "reply" ;;
    .params.path_pattern) spec_param_value "path_pattern" ;;
    .params.target) spec_param_value "target" ;;
    .params.must_include) spec_param_value "must_include" ;;
    .params.exit_code) spec_param_value "exit_code" ;;
    .params.action_description) spec_param_value "action_description" ;;
    .params.confirmed) spec_param_value "confirmed" ;;
    *) printf '' ;;
  esac
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_pair() {
  local key="$1"
  local value="$2"
  [ -n "$value" ] || return 0
  printf ',"%s":"%s"' "$(json_escape "$key")" "$(json_escape "$value")"
}

verification_json() {
  local type="$1"
  local params=""
  params="$(json_pair path_pattern "$(spec_value .params.path_pattern)")"
  params="$params$(json_pair target "$(spec_value .params.target)")"
  params="$params$(json_pair must_include "$(spec_value .params.must_include)")"
  params="$params$(json_pair exit_code "$(spec_value .params.exit_code)")"
  params="$params$(json_pair action_description "$(spec_value .params.action_description)")"
  params="$params$(json_pair confirmed "$(spec_value .params.confirmed)")"
  params="$params$(json_pair judge_for "$(spec_value .judge_for)")"
  params="$params$(json_pair prompt "$(spec_value .prompt)")"
  printf '{"type":"%s","params":{%s}}' "$(json_escape "$type")" "${params#,}"
}

require_setup() {
  if [ -z "$TENANT_ID" ] || [ -z "$SKILL_NAME" ] || [ -z "$SPEC_FILE" ]; then
    usage
    exit 2
  fi
  [ -d "$TENANT_DIR" ] || { record FAIL setup "missing tenant data directory: $TENANT_DIR"; exit 2; }
  [ -f "$SPEC_FILE" ] || { record FAIL setup "missing verification spec: $SPEC_FILE"; exit 2; }
  mkdir -p "$PROVENANCE_DIR"
  touch "$PROVENANCE_FILE"
}

path_pattern() {
  local raw="$1"
  case "$raw" in
    '~/'*) printf '%s/%s' "$FILES_DIR" "${raw#\~/files/}" ;;
    /home/hermes/files/*) printf '%s/%s' "$FILES_DIR" "${raw#/home/hermes/files/}" ;;
    /opt/data/*) printf '%s/%s' "$TENANT_DIR" "${raw#/opt/data/}" ;;
    /*) printf '%s' "$raw" ;;
    *) printf '%s/%s' "$TENANT_DIR" "$raw" ;;
  esac
}

check_file_exists_at() {
  local pattern resolved
  pattern="$(spec_value .params.path_pattern)"
  [ -n "$pattern" ] || { record FAIL file_exists_at "missing params.path_pattern"; return 1; }
  resolved="$(path_pattern "$pattern")"
  if compgen -G "$resolved" >/dev/null; then
    record PASS file_exists_at "$pattern"
    return 0
  fi
  record FAIL file_exists_at "no match: $pattern"
  return 1
}

check_file_does_not_exist_at() {
  local pattern resolved
  pattern="$(spec_value .params.path_pattern)"
  [ -n "$pattern" ] || { record FAIL file_does_not_exist_at "missing params.path_pattern"; return 1; }
  resolved="$(path_pattern "$pattern")"
  if compgen -G "$resolved" >/dev/null; then
    record FAIL file_does_not_exist_at "unexpected match: $pattern"
    return 1
  fi
  record PASS file_does_not_exist_at "$pattern"
  return 0
}

check_content_includes() {
  local target must_include resolved
  target="$(spec_value .params.target)"
  must_include="$(spec_value .params.must_include)"
  [ -n "$target" ] || { record FAIL content_includes "missing params.target"; return 1; }
  [ -n "$must_include" ] || { record FAIL content_includes "missing params.must_include"; return 1; }
  resolved="$(path_pattern "$target")"
  if [ -f "$resolved" ]; then
    if grep -Fq "$must_include" "$resolved"; then
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
  exit_code="$(spec_value .params.exit_code)"
  if [ -z "$exit_code" ] || [ "$exit_code" = "0" ]; then
    record PASS no_error_thrown "skill run completed without a recorded error"
    return 0
  fi
  record FAIL no_error_thrown "recorded exit_code=$exit_code"
  return 1
}

check_confirmation_sent_before() {
  local action confirmed
  action="$(spec_value .params.action_description)"
  confirmed="$(spec_value .params.confirmed)"
  if [ "$confirmed" = "true" ] || [ "$confirmed" = "1" ]; then
    record PASS confirmation_sent_before "${action:-irreversible action}"
    return 0
  fi
  record FAIL confirmation_sent_before "missing positive confirmation evidence for: ${action:-irreversible action}"
  return 1
}

extract_json_string() {
  local line="$1"
  local key="$2"
  sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" <<< "$line"
}

extract_json_number() {
  local line="$1"
  local key="$2"
  local value
  value="$(sed -n "s/.*\"$key\":\([0-9][0-9]*\).*/\1/p" <<< "$line")"
  printf '%s' "${value:-0}"
}

acquire_lock() {
  local i
  for i in $(seq 1 50); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  record FAIL provenance "could not acquire provenance lock"
  return 1
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

update_provenance() {
  local forced_status="$1"
  local verification_result="$2"
  local failed="$3"
  local now tmp current old_passes old_fails new_passes new_fails status last_failure verification_json_value
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$PROVENANCE_FILE.tmp.$$"
  current="$(grep -F '"skill":"'"$(json_escape "$SKILL_NAME")"'"' "$PROVENANCE_FILE" 2>/dev/null | tail -n 1 || true)"
  old_passes="$(extract_json_number "$current" pass_count)"
  old_fails="$(extract_json_number "$current" fail_count)"
  verification_json_value="$(verification_json "$TYPE")"

  if [ "$failed" = "1" ]; then
    new_passes=0
    new_fails=$((old_fails + 1))
    status="flagged"
    last_failure=',"last_failure_at":"'"$(json_escape "$now")"'"'
  else
    new_passes=$((old_passes + 1))
    new_fails="$old_fails"
    last_failure=""
    if [ "$forced_status" = "provisional" ] || [ "$TYPE" = "judge" ]; then
      status="provisional"
    elif [ "$new_passes" -ge 3 ]; then
      status="trusted"
    else
      status="provisional"
    fi
  fi

  acquire_lock || return 1
  grep -Fv '"skill":"'"$(json_escape "$SKILL_NAME")"'"' "$PROVENANCE_FILE" > "$tmp" 2>/dev/null || true
  printf '{"skill":"%s","created_at":"%s","triggering_task":"%s","verification":%s,"status":"%s","pass_count":%s,"fail_count":%s,"last_checked_at":"%s","last_result":"%s","last_verification":"%s"%s}\n' \
    "$(json_escape "$SKILL_NAME")" \
    "$(json_escape "${current:+$(extract_json_string "$current" created_at)}")" \
    "$(json_escape "${TRIGGERING_TASK:-$(extract_json_string "$current" triggering_task)}")" \
    "$verification_json_value" \
    "$(json_escape "$status")" \
    "$new_passes" \
    "$new_fails" \
    "$(json_escape "$now")" \
    "$([ "$failed" = "1" ] && printf FAIL || printf PASS)" \
    "$(json_escape "$verification_result")" \
    "$last_failure" >> "$tmp"

  if grep -q '"created_at":""' "$tmp"; then
    sed "s/\"created_at\":\"\"/\"created_at\":\"$(json_escape "$now")\"/" "$tmp" > "$tmp.fixed"
    mv "$tmp.fixed" "$tmp"
  fi
  mv "$tmp" "$PROVENANCE_FILE"
  release_lock
}

run_judge_fallback() {
  # Judge verification requires an external LLM (the admin Hermes agent) which
  # is a host-only dependency not available inside the tenant container.
  # This primitive cannot be auto-verified at runtime; it will always remain
  # status=provisional and requires operator review against the judge_for field.
  record WARN judge "verification=provisional; judge type cannot be auto-verified inside the tenant container - operator review required"
  update_provenance "provisional" "judge-not-available-in-container" 0
}

PRIMITIVES_FILE="${PRIMITIVES_FILE:-/opt/data/evals/_skill-verification-primitives-v1.yaml}"
SKILL_FILE="$TENANT_DIR/skills/${SKILL_NAME}.md"

run_credential_scan() {
  [ -f "$SKILL_FILE" ] || return 0   # no file to scan yet; spec check handles missing

  if [ ! -f "$PRIMITIVES_FILE" ]; then
    echo "FAIL  credential_scan: primitives file not found: $PRIMITIVES_FILE" >&2
    echo "      Deploy _skill-verification-primitives-v1.yaml to /opt/data/evals/ via install-tenant-scripts.sh" >&2
    exit 1
  fi

  local patterns_file="$PRIMITIVES_FILE"
  local failed=0

  # Extract credential_scan patterns from primitives YAML (simple grep
  # approach; avoids adding a yq dependency inside the tenant container).
  # Pattern lines are indented under the credential_scan type block.
  local in_cred_scan=0
  while IFS= read -r line; do
    case "$line" in
      *"type: credential_scan"*) in_cred_scan=1 ;;
      "  - type:"*) in_cred_scan=0 ;;           # next primitive block
    esac
    if [ "$in_cred_scan" = "1" ]; then
      # Extract quoted pattern strings
      pattern=$(echo "$line" | sed -n 's/.*"\(.*\)".*/\1/p')
      [ -z "$pattern" ] && continue
      if grep -Eq "$pattern" "$SKILL_FILE" 2>/dev/null; then
        record FAIL credential_scan "credential pattern detected: $pattern"
        failed=1
      fi
    fi
  done < "$patterns_file"

  if [ "$failed" = "0" ]; then
    record PASS credential_scan "no credential patterns detected"
    return 0
  fi
  # Mark skill as flagged immediately — do not evaluate agent-supplied spec
  update_provenance "flagged" "credential_scan" 1
  exit 1
}

require_setup
TYPE="$(spec_value .type)"
[ -n "$TYPE" ] || { record FAIL setup "verification spec missing type"; exit 2; }
run_credential_scan

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
