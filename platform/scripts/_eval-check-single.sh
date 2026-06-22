#!/usr/bin/env bash
set -euo pipefail

EVAL_FILE="${1:-}"
CHECK_INDEX="${2:-}"
CONTAINER="${3:-}"
EXEC_TIMEOUT_SECONDS="${4:-60}"

if [ -z "$EVAL_FILE" ] || [ -z "$CHECK_INDEX" ] || [ -z "$CONTAINER" ]; then
  printf "FAIL\tunknown\tusage: _eval-check-single.sh {eval-file} {check-index} {container} [timeout]\n"
  exit 2
fi

NAME="$(yq -r ".checks[$CHECK_INDEX].name" "$EVAL_FILE")"
PROMPT="$(yq -r ".checks[$CHECK_INDEX].prompt" "$EVAL_FILE")"
REPLY="$(timeout "$EXEC_TIMEOUT_SECONDS" docker exec "$CONTAINER" hermes -z "$PROMPT" 2>/dev/null || true)"
if [ -z "$REPLY" ]; then
  printf "FAIL\t%s\tno reply from hermes -z within %ss (container may be stuck or model call failed)\n" "$NAME" "$EXEC_TIMEOUT_SECONDS"
  exit 1
fi

CHECK_PASSED=1
REASON=""
MUST_INCLUDE_COUNT="$(yq ".checks[$CHECK_INDEX].expected.must_include | length" "$EVAL_FILE" 2>/dev/null || echo 0)"
j=0
while [ "$j" -lt "$MUST_INCLUDE_COUNT" ]; do
  TERM="$(yq -r ".checks[$CHECK_INDEX].expected.must_include[$j]" "$EVAL_FILE")"
  if ! echo "$REPLY" | grep -qi -- "$TERM"; then
    CHECK_PASSED=0
    REASON="missing required term: $TERM"
  fi
  j=$((j + 1))
done

MUST_NOT_INCLUDE_COUNT="$(yq ".checks[$CHECK_INDEX].expected.must_not_include | length" "$EVAL_FILE" 2>/dev/null || echo 0)"
j=0
while [ "$j" -lt "$MUST_NOT_INCLUDE_COUNT" ]; do
  TERM="$(yq -r ".checks[$CHECK_INDEX].expected.must_not_include[$j]" "$EVAL_FILE")"
  if echo "$REPLY" | grep -qi -- "$TERM"; then
    CHECK_PASSED=0
    REASON="contained forbidden term: $TERM"
  fi
  j=$((j + 1))
done

FILE_LOCATION="$(yq -r ".checks[$CHECK_INDEX].expected.file_location // \"\"" "$EVAL_FILE" 2>/dev/null || echo "")"
if [ -n "$FILE_LOCATION" ]; then
  REMOTE_GLOB="${FILE_LOCATION/#\~/\/home\/hermes}"
  FILE_COUNT="$(docker exec "$CONTAINER" /bin/sh -c "ls -1 ${REMOTE_GLOB}* 2>/dev/null | wc -l" 2>/dev/null || echo 0)"
  if [ "${FILE_COUNT:-0}" -lt 1 ]; then
    CHECK_PASSED=0
    REASON="no file found under $FILE_LOCATION inside $CONTAINER"
  fi
fi

if [ "$CHECK_PASSED" -eq 1 ]; then
  printf "PASS\t%s\t-\n" "$NAME"
  exit 0
else
  printf "FAIL\t%s\t%s\n" "$NAME" "$REASON"
  exit 1
fi