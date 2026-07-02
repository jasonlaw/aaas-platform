#!/usr/bin/env bash
# Best-effort reconciliation of tenant-installed plugins against the manifest
# written by tenant-install.sh. Run automatically on every container start
# by tenant-entrypoint.sh, before the gateway process takes over.
#
# This closes the gap plain persistence doesn't: files placed under
# /opt/data/lazy-packages survive a recreate, but a pip package built for a
# now-superseded Python interpreter (after an image/version upgrade) is
# stale even though the files are still on disk — the same failure mode
# native lazy_deps' own ABI stamp exists to catch. This script checks the
# same thing for tenant-initiated installs and re-runs the recorded install
# command when the ABI no longer matches, or the install target is simply
# missing (e.g. volume was recreated from scratch).
#
# Never blocks container start: every check is best-effort, failures are
# logged to stdout (visible via `docker logs`) and skipped, not fatal.
#
# Known trade-off: this script only ever reads the manifest, never rewrites
# it. After an ABI-mismatch reinstall succeeds, the manifest's recorded
# python_abi is intentionally left as-is rather than patched in place — an
# in-place YAML editor in pure shell is real bug surface for a rare event
# (an interpreter bump only happens on an image upgrade). The safe
# consequence is a harmless extra reinstall on every subsequent boot until
# the tenant is re-onboarded or the entry is corrected by hand; it never
# causes incorrect or missing state, only a few extra seconds at startup.

set -uo pipefail  # no -e: a single plugin failure must not abort the script

DATA_DIR="${HERMES_HOME:-/opt/data}"
MANIFEST="$DATA_DIR/installed-plugins.yaml"

log()  { echo "[reconcile-plugins] $1"; }
warn() { echo "[reconcile-plugins] WARN: $1"; }

if [ ! -f "$MANIFEST" ]; then
  log "No manifest at $MANIFEST — nothing to reconcile."
  exit 0
fi

current_abi() {
  local py="/opt/hermes/.venv/bin/python"
  [ -x "$py" ] || py="python3"
  "$py" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null || echo "unknown"
}

CURRENT_ABI="$(current_abi)"

# Minimal, dependency-free YAML walk: this manifest's shape is fixed and
# always written by tenant-install.sh (see record_manifest there), so a
# small state-machine parser is enough — no yq/python-yaml dependency needed.
name="" kind="" target="" install_cmd="" python_abi=""

reconcile_entry() {
  [ -n "$name" ] || return 0
  case "$kind" in
    pip)
      if [ ! -d "$target" ] || [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
        warn "'$name' missing from $target — reinstalling"
        mkdir -p "$target"
        eval "$install_cmd" && log "'$name' reinstalled" || warn "'$name' reinstall failed, continuing"
      elif [ "$python_abi" != "unknown" ] && [ "$python_abi" != "$CURRENT_ABI" ]; then
        warn "'$name' was built for $python_abi, running interpreter is $CURRENT_ABI — reinstalling"
        eval "$install_cmd" && log "'$name' reinstalled for $CURRENT_ABI" || warn "'$name' reinstall failed, continuing"
      else
        log "'$name' OK"
      fi
      ;;
    binary)
      if [ ! -x "$target" ]; then
        warn "'$name' missing or not executable at $target — reinstalling"
        mkdir -p "$(dirname "$target")"
        eval "$install_cmd" && log "'$name' reinstalled" || warn "'$name' reinstall failed, continuing"
      else
        log "'$name' OK"
      fi
      ;;
    *)
      warn "unknown kind '$kind' for '$name' — skipping"
      ;;
  esac
}

while IFS= read -r line; do
  case "$line" in
    "  - name:"*)
      reconcile_entry
      name="$(echo "$line" | sed -E 's/^  - name: *"?([^"]*)"?$/\1/')"
      kind="" target="" install_cmd="" python_abi=""
      ;;
    "    kind:"*)
      kind="$(echo "$line" | sed -E 's/^    kind: *"?([^"]*)"?$/\1/')"
      ;;
    "    target:"*)
      target="$(echo "$line" | sed -E 's/^    target: *"?([^"]*)"?$/\1/')"
      ;;
    "    install_cmd:"*)
      install_cmd="$(echo "$line" | sed -E 's/^    install_cmd: *"(.*)"$/\1/')"
      ;;
    "    python_abi:"*)
      python_abi="$(echo "$line" | sed -E 's/^    python_abi: *"?([^"]*)"?$/\1/')"
      ;;
  esac
done < "$MANIFEST"
reconcile_entry  # last entry in the file

log "Reconciliation pass complete."
