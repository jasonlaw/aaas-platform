#!/usr/bin/env bash
# Run tenant eval profiles from inside the tenant container.
# Literal checks are automated with yq, docker exec, hermes -z, and grep.
# Semantic checks are skipped by default because they require judgment
# rather than guessing at a parsing strategy.
# Literal checks run concurrently up to MAX_CONCURRENT_EVALS (default 1,
# sequential) via _eval-check-single.sh and xargs. Semantic checks (when
# USE_JUDGE=1) run sequentially after, via eval-judge.sh.

set -euo pipefail

EVAL_FILE="${1:-}"
CONTAINER="${2:-}"
EXEC_TIMEOUT_SECONDS="${EXEC_TIMEOUT_SECONDS:-60}"
USE_JUDGE="${USE_JUDGE:-0}"
PLATFORM_SCRIPTS_DIR="${PLATFORM_SCRIPTS_DIR:-/opt/aaas/platform/scripts}"
MAX_CONCURRENT_EVALS="${MAX_CONCURRENT_EVALS:-1}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

usage() {
  echo "Usage: $0 {eval-file} {container-name}"
}

if [ -z "$EVAL_FILE" ] || [ -z "$CONTAINER" ]; then
  usage
  exit 2
fi

command -v yq >/dev/null 2>&1 || { printf "FAIL\tsetup\tyq is required\n"; exit 2; }
command -v docker >/dev/null 2>&1 || { printf "FAIL\tsetup\tdocker is required\n"; exit 2; }
[ -f "$EVAL_FILE" ] || { printf "FAIL\tsetup\tmissing eval file: %s\n" "$EVAL_FILE"; exit 2; }

CHECK_COUNT="$(yq '.checks | length' "$EVAL_FILE")"
LITERAL_INDEXES="$(yq '[range(0; (.checks | length)) as $i | select(.checks[$i].match_type == "literal") | $i] | join(" ")' "$EVAL_FILE")"
SEMANTIC_INDEXES="$(yq '[range(0; (.checks | length)) as $i | select(.checks[$i].match_type == "semantic") | $i] | join(" ")' "$EVAL_FILE")"

if [ -n "$LITERAL_INDEXES" ]; then
  echo "$LITERAL_INDEXES" | tr ' ' '\n' | \
    xargs -P "$MAX_CONCURRENT_EVALS" -I {} "$PLATFORM_SCRIPTS_DIR/_eval-check-single.sh" "$EVAL_FILE" {} "$CONTAINER" "$EXEC_TIMEOUT_SECONDS" \
    > /tmp/eval-runner-literal-results.$$ 2>&1 || true
  while IFS=$'\t' read -r STATUS NAME REASON; do
    case "$STATUS" in
      PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
      FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
    printf "%s\t%s\t%s\n" "$STATUS" "$NAME" "${REASON:-}"
  done < /tmp/eval-runner-literal-results.$$
  rm -f /tmp/eval-runner-literal-results.$$
fi

for i in $SEMANTIC_INDEXES; do
  NAME="$(yq -r ".checks[$i].name" "$EVAL_FILE")"
  if [ "$USE_JUDGE" = "1" ]; then
    JUDGE_PROMPT_TEXT="$(yq -r ".checks[$i].prompt" "$EVAL_FILE")"
    JUDGE_FOR_TEXT="$(yq -r ".checks[$i].judge_for" "$EVAL_FILE")"
    JUDGE_REPLY="$(timeout "$EXEC_TIMEOUT_SECONDS" docker exec "$CONTAINER" hermes -z "$JUDGE_PROMPT_TEXT" 2>/dev/null || true)"
    if [ -z "$JUDGE_REPLY" ]; then
      printf "FAIL\t%s\tno reply from tenant agent to grade within %ss\n" "$NAME" "$EXEC_TIMEOUT_SECONDS"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
    if "$PLATFORM_SCRIPTS_DIR/eval-judge.sh" "$NAME" "$JUDGE_PROMPT_TEXT" "$JUDGE_REPLY" "$JUDGE_FOR_TEXT"; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    continue
  fi
  printf "SKIP\t%s\tmatch_type=semantic requires manual/operator review (set USE_JUDGE=1 to automate via eval-judge.sh), see judge_for in eval file\n" "$NAME"
  SKIP_COUNT=$((SKIP_COUNT + 1))
done

printf "summary\tpass=%s\tskip=%s\tfail=%s\ttotal=%s\n" "$PASS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT" "$CHECK_COUNT"
[ "$FAIL_COUNT" -eq 0 ]