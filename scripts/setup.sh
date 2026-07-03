#!/usr/bin/env bash
# =============================================================================
# AaaS Platform - Full Setup Script
# Single entrypoint for fresh installs and platform setup upgrades.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[AaaS]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

REPO_URL="https://github.com/jasonlaw/aaas-platform"
REPO_ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
REPO_ROOT=""
TMP_REPO_DIR=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --fresh           Force fresh install mode; fail if /opt/aaas/platform exists.
  --upgrade         Force upgrade mode; fail if /opt/aaas/platform is missing.
  --build-image     Build and tag hermes-tenant:latest after platform setup.
                    Not valid on fresh installs: requires agent-vault-ca.pem,
                    which is only available after Agent Vault is running.
                    Use on upgrades, or after completing setup-agent-vault SOP.
  --validate-only   Validate installed platform files without copying assets.
  --yes, --no-tty   Assume "1. Continue with backup" at setup-platform.sh's
                     version-confirm prompt instead of requiring /dev/tty.
                     For automated or headless runs.
  -h, --help        Show this help.

Without --fresh or --upgrade, the installer auto-detects:
  - Fresh mode when /opt/aaas/platform is missing.
  - Upgrade mode when /opt/aaas/platform exists.

Fresh mode runs prerequisite setup. Image build is intentionally skipped —
  Agent Vault must be configured and started first (setup-agent-vault SOP).
Upgrade mode refreshes managed platform assets and skips image build by default.
EOF
}

MODE="auto"
BUILD_IMAGE=false
VALIDATE_ONLY=false
ASSUME_YES=false

# Ensure tools installed by setup-prerequisites.sh (nvm, opencode, agent-vault)
# are on PATH for this shell session. These are no-ops if the tools aren't
# installed yet — setup-prerequisites.sh will install them and source the same
# files inside its own subprocess, then return with the tools available because
# the subprocess exports PATH as well.
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

while [ "${1:-}" != "" ]; do
  case "$1" in
    --fresh) MODE="fresh" ;;
    --upgrade) MODE="upgrade" ;;
    --build-image) BUILD_IMAGE=true ;;
    --validate-only) VALIDATE_ONLY=true ;;
    --yes|--no-tty) ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
  shift
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "$1 is required but was not found."
}

cleanup() {
  if [ -n "$TMP_REPO_DIR" ] && [ -d "$TMP_REPO_DIR" ]; then
    rm -rf "$TMP_REPO_DIR"
  fi
}

trap cleanup EXIT

resolve_repo_root() {
  if [ -n "$SCRIPT_DIR" ] \
    && [ -f "$SCRIPT_DIR/setup-prerequisites.sh" ] \
    && [ -f "$SCRIPT_DIR/setup-platform.sh" ] \
    && [ -d "$SCRIPT_DIR/../platform" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    success "Using local repository at $REPO_ROOT"
    return
  fi

  log "Local setup assets not found; downloading repository archive..."
  require_command curl
  require_command tar

  TMP_REPO_DIR="$(mktemp -d)"
  curl -fsSL "$REPO_ARCHIVE_URL" | tar -xz -C "$TMP_REPO_DIR"
  REPO_ROOT="$TMP_REPO_DIR/aaas-platform-main"

  [ -f "$REPO_ROOT/scripts/setup-prerequisites.sh" ] || error "Downloaded archive is missing scripts/setup-prerequisites.sh"
  [ -f "$REPO_ROOT/scripts/setup-platform.sh" ] || error "Downloaded archive is missing scripts/setup-platform.sh"
  [ -d "$REPO_ROOT/platform" ] || error "Downloaded archive is missing platform assets"

  success "Downloaded setup assets from $REPO_URL"
}

echo ""
echo "=============================================="
echo "  AaaS Platform - Full Setup"
echo "=============================================="
echo ""

resolve_repo_root

if [ "$MODE" = "auto" ]; then
  if [ -d /opt/aaas/platform ]; then
    MODE="upgrade"
  else
    MODE="fresh"
  fi
fi

if [ "$MODE" = "fresh" ] && [ -d /opt/aaas/platform ] && [ "$VALIDATE_ONLY" = false ]; then
  error "/opt/aaas/platform already exists. Use --upgrade or omit mode for auto-detection."
fi

if [ "$MODE" = "upgrade" ] && [ ! -d /opt/aaas/platform ]; then
  error "/opt/aaas/platform is missing. Use --fresh or omit mode for auto-detection."
fi

# --build-image on a fresh install is always premature: the image requires
# agent-vault-ca.pem, which only exists after Agent Vault has been started
# and the MITM CA fetched (setup-agent-vault SOP step 3). On a fresh server
# Agent Vault hasn't been configured yet (master password not set, container
# not running), so the build would fail regardless. Reject early — before
# running prerequisites, which take significant time — so the operator
# doesn't wait through a full install only to hit an error at the very end.
if [ "$MODE" = "fresh" ] && [ "$BUILD_IMAGE" = true ] && [ "$VALIDATE_ONLY" = false ]; then
  error "--build-image cannot be used on a fresh install.
  The tenant Docker image requires the Agent Vault MITM CA certificate
  (agent-vault-ca.pem), which is only available after Agent Vault has been
  started and set up (setup-agent-vault SOP step 3).

  Run the installer without --build-image first:
    bash <(curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh)

  Then follow the post-install next steps to start Agent Vault, and build
  the image afterwards via the admin agent or:
    /opt/aaas/platform/scripts/setup-platform.sh --build-image"
fi

if [ "$VALIDATE_ONLY" = true ]; then
  log "Validate-only mode selected"
elif [ "$MODE" = "fresh" ]; then
  log "Running prerequisite bootstrap..."
  bash "$REPO_ROOT/scripts/setup-prerequisites.sh"
else
  log "Existing platform detected; running platform upgrade without prerequisite bootstrap"
fi

PLAN_A_ARGS=()
if [ "$VALIDATE_ONLY" = true ]; then
  PLAN_A_ARGS+=(--validate-only)
fi

if [ "$ASSUME_YES" = true ]; then
  PLAN_A_ARGS+=(--yes)
fi

# NOTE: Fresh installs do NOT auto-enable --build-image here.
# Building the tenant image requires agent-vault-ca.pem, which is fetched
# from Agent Vault only after the container is running (setup-agent-vault
# SOP step 3). On a fresh install Agent Vault has not been started yet
# (master password not set), so forcing an image build here always fails.
# The image is built later via the admin agent ("Complete the Agent Vault
# setup") or by passing --build-image to setup-platform.sh after finishing
# the setup-agent-vault SOP.

if [ "$BUILD_IMAGE" = true ] && [ "$VALIDATE_ONLY" = false ]; then
  PLAN_A_ARGS+=(--build-image)
fi

if [ "$MODE" = "upgrade" ]; then
  log "Running platform upgrade..."
else
  log "Running platform setup..."
fi
bash "$REPO_ROOT/scripts/setup-platform.sh" "${PLAN_A_ARGS[@]}"

echo ""
echo "=============================================="
echo -e "  ${GREEN}AaaS Platform full setup complete${NC}"
echo "=============================================="
echo ""
echo "Mode: $MODE"
if [ "$BUILD_IMAGE" = true ] && [ "$VALIDATE_ONLY" = false ]; then
  echo "Docker image build: completed"
else
  echo "Docker image build: skipped"
fi
echo ""
echo "Next steps:"
echo "  1. Open the platform path before starting OpenCode:"
echo "       cd /opt/aaas/platform"
echo "       opencode"
echo ""
echo "  Note: if you ran this script via 'curl | bash', tools like opencode and"
echo "  nvm may not be on PATH in your current terminal (a piped subshell cannot"
echo "  export environment changes back to the parent shell). Run:"
echo "       exec bash"
echo "  to reload your shell and pick up ~/.bashrc before running opencode."
echo ""
echo "  2. Ask OpenCode to onboard tenants, build or upgrade images, monitor health,"
echo "     review logs, suspend/reactivate tenants, or update tenant configuration."
echo ""
