#!/usr/bin/env bash
# =============================================================================
# AaaS Platform - Plan A OpenCode Admin Agent Setup
# Version: 1.0
# Run after scripts/setup-plan-0.sh / Plan 0 has completed inside WSL2 Ubuntu.
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

INSTALL_ROOT="/opt/aaas"
PLATFORM_ROOT="$INSTALL_ROOT/platform"
REPO_URL="https://github.com/jasonlaw/aaas-platform"
REPO_ARCHIVE_URL="https://github.com/jasonlaw/aaas-platform/archive/refs/heads/main.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
REPO_ROOT=""
ASSET_ROOT=""
TMP_ASSET_DIR=""
BUILD_IMAGE=false
VALIDATE_ONLY=false

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --build-image     Build and tag hermes-tenant:latest after installing files.
  --validate-only   Check prerequisites and installed files without copying.
  -h, --help        Show this help.
EOF
}

while [ "${1:-}" != "" ]; do
  case "$1" in
    --build-image) BUILD_IMAGE=true ;;
    --validate-only) VALIDATE_ONLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
  shift
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "$1 is required. Complete Plan 0 first."
}

copy_tree() {
  local source="$1"
  local target="$2"
  mkdir -p "$target"
  cp -a "$source"/. "$target"/
}

cleanup() {
  if [ -n "$TMP_ASSET_DIR" ] && [ -d "$TMP_ASSET_DIR" ]; then
    rm -rf "$TMP_ASSET_DIR"
  fi
}

trap cleanup EXIT

resolve_asset_root() {
  if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/../platform" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    ASSET_ROOT="$REPO_ROOT/platform"
    success "Using local repository assets from $ASSET_ROOT"
    return
  fi

  log "Local platform assets not found; downloading repository archive..."
  require_command curl
  require_command tar

  TMP_ASSET_DIR="$(mktemp -d)"
  curl -fsSL "$REPO_ARCHIVE_URL" | tar -xz -C "$TMP_ASSET_DIR"

  REPO_ROOT="$TMP_ASSET_DIR/aaas-platform-main"
  ASSET_ROOT="$REPO_ROOT/platform"
  [ -d "$ASSET_ROOT" ] || error "Downloaded archive did not contain platform assets from $REPO_URL"
  success "Downloaded repository assets from $REPO_URL"
}

ensure_plan0_ready() {
  log "Checking Plan 0 prerequisites..."
  require_command git
  require_command docker
  require_command opencode

  [ -d "$INSTALL_ROOT" ] || error "$INSTALL_ROOT does not exist. Run scripts/setup-plan-0.sh first."
  [ -d "$PLATFORM_ROOT" ] || error "$PLATFORM_ROOT does not exist. Run scripts/setup-plan-0.sh first."

  docker --version >/dev/null
  opencode --version >/dev/null
  success "Plan 0 tools and folders are present"
}

install_assets() {
  log "Installing Plan A OpenCode admin assets..."

  mkdir -p "$PLATFORM_ROOT/sop"
  mkdir -p "$PLATFORM_ROOT/templates"
  mkdir -p "$PLATFORM_ROOT/docker"
  mkdir -p "$INSTALL_ROOT/tenants"

  copy_tree "$ASSET_ROOT/sop" "$PLATFORM_ROOT/sop"
  copy_tree "$ASSET_ROOT/templates" "$PLATFORM_ROOT/templates"
  cp "$ASSET_ROOT/AGENTS.md" "$PLATFORM_ROOT/AGENTS.md"
  cp "$ASSET_ROOT/docker/Dockerfile" "$PLATFORM_ROOT/docker/Dockerfile"

  if [ ! -f "$PLATFORM_ROOT/tenants.yaml" ]; then
    cat > "$PLATFORM_ROOT/tenants.yaml" <<'EOF'
# AaaS Platform - Tenant Registry
# Business metadata only - secrets live in per-tenant .env files
# Container management is in docker-compose.yaml
# Status values: active | suspended | offboarded

tenants: []
EOF
    success "Created tenants.yaml"
  else
    warn "tenants.yaml already exists - leaving it unchanged"
  fi

  if [ ! -f "$PLATFORM_ROOT/docker/docker-compose.yaml" ]; then
    cat > "$PLATFORM_ROOT/docker/docker-compose.yaml" <<'EOF'
# AaaS Platform - Tenant Container Registry
# Managed by OpenCode admin agent
# OpenCode adds one service block per tenant under services:
# Always specify service name when running docker compose commands
# to avoid affecting ALL tenants unintentionally

services:
  # Tenant services are added here by OpenCode during onboarding.
EOF
    success "Created docker-compose.yaml"
  else
    warn "docker-compose.yaml already exists - leaving it unchanged"
  fi

  success "Plan A assets installed under $PLATFORM_ROOT"
}

build_image() {
  log "Building Hermes tenant Docker image..."
  require_command docker
  cd "$PLATFORM_ROOT/docker"
  docker pull nousresearch/hermes-agent:latest
  docker build -t hermes-tenant:latest .
  docker tag hermes-tenant:latest hermes-tenant:v1.0
  docker images | grep hermes-tenant
  success "Docker image built and tagged as hermes-tenant:latest and hermes-tenant:v1.0"
}

validate_install() {
  log "Validating Plan A files..."

  local required=(
    "$PLATFORM_ROOT/AGENTS.md"
    "$PLATFORM_ROOT/docker/Dockerfile"
    "$PLATFORM_ROOT/sop/build-image.md"
    "$PLATFORM_ROOT/sop/onboard-tenant.md"
    "$PLATFORM_ROOT/sop/suspend-tenant.md"
    "$PLATFORM_ROOT/sop/reactivate-tenant.md"
    "$PLATFORM_ROOT/sop/offboard-tenant.md"
    "$PLATFORM_ROOT/sop/update-tenant.md"
    "$PLATFORM_ROOT/sop/upgrade-tenants.md"
    "$PLATFORM_ROOT/sop/monitor-health.md"
    "$PLATFORM_ROOT/sop/monitor-logs.md"
    "$PLATFORM_ROOT/templates/_base/config.yaml.template"
    "$PLATFORM_ROOT/templates/_base/env.template"
    "$PLATFORM_ROOT/templates/_base/SOUL.md.template"
    "$PLATFORM_ROOT/templates/_base/USER.md.template"
    "$PLATFORM_ROOT/templates/verticals/fnb/SOUL.md.template"
    "$PLATFORM_ROOT/templates/verticals/fnb/MEMORY.md.template"
    "$PLATFORM_ROOT/templates/verticals/fnb/USER.md.template"
    "$PLATFORM_ROOT/tenants.yaml"
    "$PLATFORM_ROOT/docker/docker-compose.yaml"
  )

  for path in "${required[@]}"; do
    [ -f "$path" ] || error "Missing required file: $path"
  done

  grep -q "memory_enabled: false" "$PLATFORM_ROOT/templates/_base/config.yaml.template" \
    || error "Base config template must disable native Hermes memory"
  grep -q "mnemosyne" "$PLATFORM_ROOT/templates/_base/config.yaml.template" \
    || error "Base config template must enable Mnemosyne"

  success "Plan A validation passed"
}

echo ""
echo "=============================================="
echo "  AaaS Platform - Plan A OpenCode Setup"
echo "=============================================="
echo ""

ensure_plan0_ready

if [ "$VALIDATE_ONLY" = false ]; then
  resolve_asset_root
  install_assets
else
  warn "Validate-only mode - no files will be copied"
fi

validate_install

if [ "$BUILD_IMAGE" = true ]; then
  build_image
else
  warn "Skipping Docker image build. Run with --build-image when ready."
fi

echo ""
echo "=============================================="
echo -e "  ${GREEN}Plan A OpenCode setup complete${NC}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. cd /opt/aaas/platform"
echo "  2. opencode"
echo "  3. Ask: what skills do you have available?"
echo "  4. When ready, build the image with:"
echo "       curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup-plan-a.sh | bash -s -- --build-image"
echo ""
