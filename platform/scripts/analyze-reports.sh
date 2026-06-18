#!/usr/bin/env bash
# Summarize recent report index entries for platform improvement decisions.

set -euo pipefail

PLATFORM_ROOT="${PLATFORM_ROOT:-/opt/aaas/platform}"
INDEX="${1:-$PLATFORM_ROOT/reports/INDEX.jsonl}"
LIMIT="${LIMIT:-100}"

if [ ! -f "$INDEX" ]; then
  echo "No report index found: $INDEX"
  exit 0
fi

echo "AaaS report analysis"
echo "index=$INDEX"
echo "limit=$LIMIT"
echo ""

if command -v jq >/dev/null 2>&1; then
  echo "Top issues"
  tail -n "$LIMIT" "$INDEX" | jq -r '.issues[]? // empty' 2>/dev/null | sort | uniq -c | sort -rn | head -10 || true
  echo ""
  echo "Top improvement signals"
  tail -n "$LIMIT" "$INDEX" | jq -r '.improvement_signals[]? // empty' 2>/dev/null | sort | uniq -c | sort -rn | head -10 || true
  echo ""
  echo "Partial/failed by SOP"
  tail -n "$LIMIT" "$INDEX" | jq -r 'select(.status == "failed" or .status == "partial") | .sop' 2>/dev/null | sort | uniq -c | sort -rn || true
  echo ""
  echo "Pending next actions"
  tail -n "$LIMIT" "$INDEX" | jq -r '.next_action? // empty' 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -10 || true
else
  echo "jq is not installed; showing recent raw summaries."
  tail -n "$LIMIT" "$INDEX" | grep -E '"status":"(failed|partial)"|"improvement_signals"|"next_action"' || true
fi
