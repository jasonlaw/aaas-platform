#!/usr/bin/env bash
# Install a runtime plugin (pip package or standalone binary) to a location
# that survives `docker compose up --force-recreate`, and record it in this
# tenant's install manifest so a reconciliation pass can restore it later if
# needed (see reconcile-plugins.sh, run automatically by tenant-entrypoint.sh
# on every container start).
#
# Runs inside the tenant container, using /opt/data (the one mounted,
# persistent volume — see docs/architecture.md's "What Gets Preserved on
# Upgrade" and tenant-plugin-persistence-issue.md for why nothing outside it
# survives a recreate). This is the ONLY supported way for the tenant agent
# to add a new pip package or binary at runtime — never call pip/uv/apt or
# write into /opt/hermes/.venv directly; that venv is root-owned and
# read-only to the tenant agent by design (see Dockerfile), and mutating it
# live can crash the running gateway process, not just fail to persist.
#
# Usage:
#   tenant-install.sh pip    <package-spec> "<reason>"
#   tenant-install.sh binary <name> <download-url> "<reason>"
#
# Examples:
#   tenant-install.sh pip pypdf "owner asked for PDF text extraction"
#   tenant-install.sh binary jq https://github.com/jqlang/jq/releases/.../jq-linux-amd64 "owner asked for JSON filtering in shell steps"

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
  exit 2
}

log()  { echo "[tenant-install] $1"; }
fail() { echo "[tenant-install] ERROR: $1" >&2; exit 1; }

abi_tag() {
  # Captures the interpreter ABI so reconcile-plugins.sh can tell a
  # pip-installed package is stale after an image/interpreter upgrade,
  # the same staleness native lazy_deps guards against with its own stamp.
  local py="/opt/hermes/.venv/bin/python"
  [ -x "$py" ] || py="python3"
  "$py" -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null || echo "unknown"
}

record_manifest() {
  local name="$1" kind="$2" target="$3" install_cmd="$4" reason="$5"
  case "$name$target$install_cmd$reason" in
    *'"'*|*$'\n'*) fail "install metadata cannot contain a double-quote or newline (name/target/reason)" ;;
  esac
  mkdir -p "$DATA_DIR"
  [ -f "$MANIFEST" ] || echo "plugins:" > "$MANIFEST"
  cat >> "$MANIFEST" <<EOF
  - name: "$name"
    kind: "$kind"
    target: "$target"
    install_cmd: "$install_cmd"
    python_abi: "$(abi_tag)"
    installed_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "$reason"
EOF
  log "Recorded '$name' in $MANIFEST"
}

[ "$#" -ge 1 ] || usage
KIND="$1"

case "$KIND" in
  pip)
    [ "$#" -eq 3 ] || usage
    PACKAGE="$2"
    REASON="$3"
    mkdir -p "$LAZY_TARGET"
    # No embedded double-quotes here deliberately: this string is stored as a
    # double-quoted YAML scalar in the manifest (see record_manifest below),
    # and paths on this platform are always fixed, space-free strings, so
    # quoting isn't needed and would only make the manifest harder to parse
    # back out correctly.
    INSTALL_CMD="uv pip install --target $LAZY_TARGET --no-cache-dir $PACKAGE"
    log "Installing pip package '$PACKAGE' into $LAZY_TARGET"
    uv pip install --target "$LAZY_TARGET" --no-cache-dir "$PACKAGE" \
      || fail "pip install of '$PACKAGE' failed"
    record_manifest "$PACKAGE" "pip" "$LAZY_TARGET" "$INSTALL_CMD" "$REASON"
    ;;
  binary)
    [ "$#" -eq 4 ] || usage
    NAME="$2"
    URL="$3"
    REASON="$4"
    case "$NAME" in
      */*) fail "binary name must not contain '/' (got '$NAME') — this installs a single file directly into $BIN_TARGET, not an arbitrary path" ;;
    esac
    DEST="$BIN_TARGET/$NAME"
    case "$DEST" in
      "$FORBIDDEN_PREFIX"*) fail "refusing to install into $FORBIDDEN_PREFIX — that runtime venv is off-limits, see comment at top of this script" ;;
    esac
    mkdir -p "$BIN_TARGET"
    # See note above: no embedded double-quotes, kept parseable back out of
    # the YAML manifest without an escaping scheme.
    INSTALL_CMD="curl -sSL $URL -o $DEST && chmod +x $DEST"
    log "Installing binary '$NAME' to $DEST"
    curl -sSL "$URL" -o "$DEST" || fail "download of '$NAME' from $URL failed"
    chmod +x "$DEST"
    record_manifest "$NAME" "binary" "$DEST" "$INSTALL_CMD" "$REASON"
    ;;
  *)
    usage
    ;;
esac

log "Done. Available immediately in this session; persists across container recreation."
