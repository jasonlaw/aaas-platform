#!/usr/bin/env bash
# =============================================================================
# AaaS Platform - Full Setup Script
# Version: 1.0
# Run once inside Ubuntu/Linux. This combines Plan 0 prerequisites and Plan A
# OpenCode platform setup, then always builds the Hermes tenant Docker image.
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
  --skip-plan-0     Skip prerequisite bootstrap and run only platform install.
  --validate-only   Validate installed platform files without copying assets.
  -h, --help        Show this help.

This installer always builds hermes-tenant:latest after setup.
EOF
}

SKIP_PLAN_0=false
VALIDATE_ONLY=false

while [ "${1:-}" != "" ]; do
  case "$1" in
    --skip-plan-0) SKIP_PLAN_0=true ;;
    --validate-only) VALIDATE_ONLY=true ;;
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
    && [ -f "$SCRIPT_DIR/setup-plan-0.sh" ] \
    && [ -f "$SCRIPT_DIR/setup-plan-a.sh" ] \
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

  [ -f "$REPO_ROOT/scripts/setup-plan-0.sh" ] || error "Downloaded archive is missing scripts/setup-plan-0.sh"
  [ -f "$REPO_ROOT/scripts/setup-plan-a.sh" ] || error "Downloaded archive is missing scripts/setup-plan-a.sh"
  [ -d "$REPO_ROOT/platform" ] || error "Downloaded archive is missing platform assets"

  success "Downloaded setup assets from $REPO_URL"
}

echo ""
echo "=============================================="
echo "  AaaS Platform - Full Setup"
echo "=============================================="
echo ""

resolve_repo_root

if [ "$SKIP_PLAN_0" = false ]; then
  log "Running Plan 0 prerequisite bootstrap..."
  bash "$REPO_ROOT/scripts/setup-plan-0.sh"
else
  warn "Skipping Plan 0 prerequisite bootstrap"
fi

PLAN_A_ARGS=(--build-image)
if [ "$VALIDATE_ONLY" = true ]; then
  PLAN_A_ARGS+=(--validate-only)
fi

log "Running Plan A OpenCode setup and Docker image build..."
bash "$REPO_ROOT/scripts/setup-plan-a.sh" "${PLAN_A_ARGS[@]}"

echo ""
echo "=============================================="
echo -e "  ${GREEN}AaaS Platform full setup complete${NC}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Open the platform path before starting OpenCode:"
echo "       cd /opt/aaas/platform"
echo "       opencode"
echo ""
echo "  2. Ask OpenCode to onboard tenants, build or upgrade images, monitor health,"
echo "     review logs, suspend/reactivate tenants, or update tenant configuration."
echo ""
