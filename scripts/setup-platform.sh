#!/usr/bin/env bash
# =============================================================================
# AaaS Platform - Platform Asset Setup
# Platform version is read from platform/VERSION.
# Run after scripts/setup-prerequisites.sh has completed inside Ubuntu/Linux.
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
BACKUP_BEFORE_INSTALL=true

usage() {
  cat <<EOF
Usage: $0 [options]

Installs or upgrades managed platform assets while preserving tenant
data, tenants.yaml, docker-compose.yaml, reports, and report index history.

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
  command -v "$1" >/dev/null 2>&1 || error "$1 is required. Complete prerequisite setup first."
}

copy_tree() {
  local source="$1"
  local target="$2"
  [ -d "$source" ] || error "Missing source directory: $source"
  mkdir -p "$target"
  cp -a "$source"/. "$target"/
}

read_version() {
  local path="$1"
  [ -f "$path" ] || return 1
  tr -d '[:space:]' < "$path"
}

version_compare() {
  local left="$1"
  local right="$2"

  if [ "$left" = "$right" ]; then
    echo "equal"
  elif [ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | head -n 1)" = "$left" ]; then
    echo "older"
  else
    echo "newer"
  fi
}

prompt_confirm_install() {
  local installed_version="$1"
  local source_version="$2"
  local answer=""

  if [ "$installed_version" = "$source_version" ]; then
    warn "Installed platform version already matches repository version: $installed_version"
    warn "Rerunning setup will overwrite managed assets with the same version."
  else
    warn "Installed platform version is $installed_version; repository version is $source_version"
    warn "Continuing will overwrite managed assets with the repository version."
  fi
  echo ""
  echo "Choose how to continue:"
  echo "  1. Continue with backup"
  echo "  2. Continue without backup"
  echo "  3. Cancel"
  echo ""

  if [ -r /dev/tty ]; then
    while true; do
      printf "Selection [1-3]: " > /dev/tty
      IFS= read -r answer < /dev/tty || answer=""
      case "$answer" in
        1)
          BACKUP_BEFORE_INSTALL=true
          log "Continuing with backup for version $source_version"
          return
          ;;
        2)
          BACKUP_BEFORE_INSTALL=false
          warn "Continuing without backup for version $source_version"
          return
          ;;
        3)
          error "Cancelled by operator"
          ;;
        *)
          warn "Enter 1, 2, or 3."
          ;;
      esac
    done
  fi

  error "Platform version confirmation is required, but no interactive terminal is available."
}

decide_install_strategy() {
  local installed_version=""
  local source_version=""
  local comparison=""

  source_version="$(read_version "$ASSET_ROOT/VERSION")" \
    || error "Repository asset missing: $ASSET_ROOT/VERSION"

  if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$ASSET_ROOT/VERSION"; then
    error "Repository VERSION must contain a semantic version like 0.1.0"
  fi

  if ! installed_version="$(read_version "$PLATFORM_ROOT/VERSION")"; then
    warn "Installed platform VERSION is missing - installing repository version $source_version"
    BACKUP_BEFORE_INSTALL=false
    return
  fi

  if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$PLATFORM_ROOT/VERSION"; then
    warn "Installed platform VERSION is invalid: $installed_version"
    warn "Proceeding with backup before installing repository version $source_version"
    BACKUP_BEFORE_INSTALL=true
    return
  fi

  comparison="$(version_compare "$installed_version" "$source_version")"
  case "$comparison" in
    older)
      log "Installed platform version $installed_version is older than repository version $source_version"
      BACKUP_BEFORE_INSTALL=true
      ;;
    equal)
      prompt_confirm_install "$installed_version" "$source_version"
      ;;
    newer)
      warn "Installed platform version $installed_version is newer than repository version $source_version"
      warn "This may downgrade managed platform assets."
      prompt_confirm_install "$installed_version" "$source_version"
      ;;
  esac
}

validate_asset_source() {
  local required=(
    "$ASSET_ROOT/AGENTS.md"
    "$ASSET_ROOT/VERSION"
    "$REPO_ROOT/CHANGELOG.md"
    "$ASSET_ROOT/admin-hermes/SOUL.md.template"
    "$ASSET_ROOT/admin-hermes/USER.md.template"
    "$ASSET_ROOT/admin-hermes/MEMORY.md.template"
    "$ASSET_ROOT/admin-hermes/config.yaml.template"
    "$ASSET_ROOT/admin-hermes/env.template"
    "$ASSET_ROOT/docker/Dockerfile"
    "$ASSET_ROOT/harness/check-tenant.sh"
    "$ASSET_ROOT/harness/tenant-harness.yaml.template"
    "$ASSET_ROOT/harness/ACCEPTANCE.md.template"
    "$ASSET_ROOT/checklists/onboard-tenant.required.json"
    "$ASSET_ROOT/checklists/monitor-health.required.json"
    "$ASSET_ROOT/evals/tenant-agent/_fixed-safety-v1.yaml"
    "$ASSET_ROOT/evals/tenant-agent/generated/.gitkeep"
    "$ASSET_ROOT/evals/admin-agent/meta-eval-generation-v1.yaml"
    "$ASSET_ROOT/scripts/preflight-check.sh"
    "$ASSET_ROOT/scripts/validate-tenant-config.sh"
    "$ASSET_ROOT/scripts/analyze-reports.sh"
    "$ASSET_ROOT/scripts/eval-runner.sh"
    "$ASSET_ROOT/scripts/eval-judge.sh"
    "$ASSET_ROOT/scripts/_eval-check-single.sh"
    "$ASSET_ROOT/incidents/all-tenants-no-connectivity.md"
    "$ASSET_ROOT/incidents/docker-version-rollback.md"
    "$ASSET_ROOT/incidents/telegram-api-change.md"
    "$ASSET_ROOT/incidents/mnemosyne-seed-corruption.md"
    "$ASSET_ROOT/incidents/platform-backup-recovery.md"
    "$ASSET_ROOT/skills/grill-me.md"
    "$ASSET_ROOT/skills/setup-admin-hermes.md"
    "$ASSET_ROOT/sop/build-image.md"
    "$ASSET_ROOT/sop/upgrade-platform.md"
    "$ASSET_ROOT/sop/onboard-tenant.md"
    "$ASSET_ROOT/sop/suspend-tenant.md"
    "$ASSET_ROOT/sop/reactivate-tenant.md"
    "$ASSET_ROOT/sop/offboard-tenant.md"
    "$ASSET_ROOT/sop/update-tenant.md"
    "$ASSET_ROOT/sop/upgrade-tenants.md"
    "$ASSET_ROOT/sop/monitor-health.md"
    "$ASSET_ROOT/sop/monitor-logs.md"
    "$ASSET_ROOT/sop/troubleshoot-tenant.md"
    "$ASSET_ROOT/sop/write-report.md"
    "$ASSET_ROOT/templates/_base/config.yaml.template"
    "$ASSET_ROOT/templates/_base/env.template"
    "$ASSET_ROOT/templates/_base/SOUL.md.template"
    "$ASSET_ROOT/templates/_base/USER.md.template"
    "$ASSET_ROOT/templates/_base/MEMORY.md.template"
  )

  for path in "${required[@]}"; do
    [ -f "$path" ] || error "Repository asset missing: $path"
  done
}

validate_installed_matches_source() {
  [ -n "$ASSET_ROOT" ] || return

  local relative_paths=(
    "AGENTS.md"
    "VERSION"
    "admin-hermes/SOUL.md.template"
    "admin-hermes/USER.md.template"
    "admin-hermes/MEMORY.md.template"
    "admin-hermes/config.yaml.template"
    "admin-hermes/env.template"
    "docker/Dockerfile"
    "harness/check-tenant.sh"
    "harness/tenant-harness.yaml.template"
    "harness/ACCEPTANCE.md.template"
    "checklists/onboard-tenant.required.json"
    "checklists/monitor-health.required.json"
    "evals/tenant-agent/_fixed-safety-v1.yaml"
    "evals/tenant-agent/generated/.gitkeep"
    "evals/admin-agent/meta-eval-generation-v1.yaml"
    "scripts/preflight-check.sh"
    "scripts/validate-tenant-config.sh"
    "scripts/analyze-reports.sh"
    "scripts/eval-runner.sh"
    "scripts/eval-judge.sh"
    "scripts/_eval-check-single.sh"
    "scripts/tenant/skill-verify.sh"
    "incidents/all-tenants-no-connectivity.md"
    "incidents/docker-version-rollback.md"
    "incidents/telegram-api-change.md"
    "incidents/mnemosyne-seed-corruption.md"
    "incidents/platform-backup-recovery.md"
    "skills/grill-me.md"
    "skills/setup-admin-hermes.md"
    "sop/build-image.md"
    "sop/upgrade-platform.md"
    "sop/onboard-tenant.md"
    "sop/suspend-tenant.md"
    "sop/reactivate-tenant.md"
    "sop/offboard-tenant.md"
    "sop/update-tenant.md"
    "sop/upgrade-tenants.md"
    "sop/monitor-health.md"
    "sop/monitor-logs.md"
    "sop/troubleshoot-tenant.md"
    "sop/write-report.md"
    "templates/_base/config.yaml.template"
    "templates/_base/env.template"
    "templates/_base/SOUL.md.template"
    "templates/_base/USER.md.template"
    "templates/_base/MEMORY.md.template"
  )

  for relative_path in "${relative_paths[@]}"; do
    cmp -s "$ASSET_ROOT/$relative_path" "$PLATFORM_ROOT/$relative_path" \
      || error "Installed asset differs from repository asset: $relative_path"
  done

  cmp -s "$REPO_ROOT/CHANGELOG.md" "$PLATFORM_ROOT/CHANGELOG.md" \
    || error "Installed asset differs from repository asset: CHANGELOG.md"
}

backup_managed_assets() {
  local existing=false
  local timestamp=""
  local backup_dir=""
  local relative_path=""
  local paths=(
    "AGENTS.md"
    "VERSION"
    "CHANGELOG.md"
    "admin-hermes"
    "docker/Dockerfile"
    "harness"
    "checklists"
    "evals"
    "incidents"
    "sop"
    "skills"
    "templates"
    "scripts"
  )

  for relative_path in "${paths[@]}"; do
    if [ -e "$PLATFORM_ROOT/$relative_path" ]; then
      existing=true
      break
    fi
  done

  [ "$existing" = true ] || return

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_dir="$PLATFORM_ROOT/backups/platform-assets-$timestamp"
  mkdir -p "$backup_dir"

  for relative_path in "${paths[@]}"; do
    if [ -e "$PLATFORM_ROOT/$relative_path" ]; then
      mkdir -p "$backup_dir/$(dirname "$relative_path")"
      cp -a "$PLATFORM_ROOT/$relative_path" "$backup_dir/$relative_path"
    fi
  done

  success "Backed up existing managed platform assets to $backup_dir"
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
  log "Checking prerequisite setup..."
  require_command git
  require_command docker
  require_command opencode

  [ -d "$INSTALL_ROOT" ] || error "$INSTALL_ROOT does not exist. Run scripts/setup-prerequisites.sh first."
  [ -d "$PLATFORM_ROOT" ] || error "$PLATFORM_ROOT does not exist. Run scripts/setup-prerequisites.sh first."

  docker --version >/dev/null
  docker info >/dev/null 2>&1 || error "Docker Engine is not reachable. Start Docker, then rerun platform setup."
  opencode --version >/dev/null
  success "Prerequisite tools and folders are present"
}

install_assets() {
  log "Installing platform assets..."
  validate_asset_source
  decide_install_strategy

  mkdir -p "$PLATFORM_ROOT/sop"
  mkdir -p "$PLATFORM_ROOT/skills"
  mkdir -p "$PLATFORM_ROOT/reports"
  mkdir -p "$PLATFORM_ROOT/backups"
  mkdir -p "$PLATFORM_ROOT/templates"
  mkdir -p "$PLATFORM_ROOT/docker"
  mkdir -p "$PLATFORM_ROOT/admin-hermes"
  mkdir -p "$PLATFORM_ROOT/harness"
  mkdir -p "$PLATFORM_ROOT/checklists"
  mkdir -p "$PLATFORM_ROOT/evals"
  mkdir -p "$PLATFORM_ROOT/incidents"
  mkdir -p "$PLATFORM_ROOT/scripts"
  mkdir -p "$INSTALL_ROOT/tenants"

  if [ "$BACKUP_BEFORE_INSTALL" = true ]; then
    backup_managed_assets
  else
    warn "Skipping managed asset backup for this install"
  fi

  copy_tree "$ASSET_ROOT/sop" "$PLATFORM_ROOT/sop"
  copy_tree "$ASSET_ROOT/skills" "$PLATFORM_ROOT/skills"
  copy_tree "$ASSET_ROOT/templates" "$PLATFORM_ROOT/templates"
  copy_tree "$ASSET_ROOT/admin-hermes" "$PLATFORM_ROOT/admin-hermes"
  copy_tree "$ASSET_ROOT/harness" "$PLATFORM_ROOT/harness"
  copy_tree "$ASSET_ROOT/checklists" "$PLATFORM_ROOT/checklists"
  copy_tree "$ASSET_ROOT/evals" "$PLATFORM_ROOT/evals"
  copy_tree "$ASSET_ROOT/incidents" "$PLATFORM_ROOT/incidents"
  copy_tree "$ASSET_ROOT/scripts" "$PLATFORM_ROOT/scripts"
  mkdir -p "$PLATFORM_ROOT/scripts/tenant"
  chmod +x "$PLATFORM_ROOT/harness/check-tenant.sh"
  chmod +x "$PLATFORM_ROOT/scripts/preflight-check.sh"
  chmod +x "$PLATFORM_ROOT/scripts/validate-tenant-config.sh"
  chmod +x "$PLATFORM_ROOT/scripts/analyze-reports.sh"
  chmod +x "$PLATFORM_ROOT/scripts/eval-runner.sh"
  chmod +x "$PLATFORM_ROOT/scripts/eval-judge.sh"
  chmod +x "$PLATFORM_ROOT/scripts/_eval-check-single.sh"
  chmod +x "$PLATFORM_ROOT/scripts/tenant/skill-verify.sh"
  cp "$ASSET_ROOT/AGENTS.md" "$PLATFORM_ROOT/AGENTS.md"
  cp "$ASSET_ROOT/VERSION" "$PLATFORM_ROOT/VERSION"
  cp "$REPO_ROOT/CHANGELOG.md" "$PLATFORM_ROOT/CHANGELOG.md"
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
# Managed by the AaaS admin agent
# The admin agent adds one service block per tenant under services:
# Always specify service name when running docker compose commands
# to avoid affecting ALL tenants unintentionally

services:
  # Tenant services are added here by the admin agent during onboarding.
EOF
    success "Created docker-compose.yaml"
  else
    warn "docker-compose.yaml already exists - leaving it unchanged"
  fi

  if [ ! -f "$PLATFORM_ROOT/reports/INDEX.jsonl" ]; then
    touch "$PLATFORM_ROOT/reports/INDEX.jsonl"
    success "Created reports/INDEX.jsonl"
  else
    warn "reports/INDEX.jsonl already exists - leaving it unchanged"
  fi

  success "Platform assets installed under $PLATFORM_ROOT"
}

build_image() {
  log "Building Hermes tenant Docker image..."
  require_command docker
  [ -f "$PLATFORM_ROOT/docker/Dockerfile" ] || error "Missing Dockerfile. Run platform setup before --build-image."
  cd "$PLATFORM_ROOT/docker"
  docker pull nousresearch/hermes-agent:latest
  docker build -t hermes-tenant:latest .
  docker tag hermes-tenant:latest hermes-tenant:v1.0
  docker images | grep hermes-tenant
  success "Docker image built and tagged as hermes-tenant:latest and hermes-tenant:v1.0"
}

validate_install() {
  log "Validating platform files..."

  local required=(
    "$PLATFORM_ROOT/AGENTS.md"
    "$PLATFORM_ROOT/VERSION"
    "$PLATFORM_ROOT/CHANGELOG.md"
    "$PLATFORM_ROOT/admin-hermes/SOUL.md.template"
    "$PLATFORM_ROOT/admin-hermes/USER.md.template"
    "$PLATFORM_ROOT/admin-hermes/MEMORY.md.template"
    "$PLATFORM_ROOT/admin-hermes/config.yaml.template"
    "$PLATFORM_ROOT/admin-hermes/env.template"
    "$PLATFORM_ROOT/docker/Dockerfile"
    "$PLATFORM_ROOT/harness/check-tenant.sh"
    "$PLATFORM_ROOT/harness/tenant-harness.yaml.template"
    "$PLATFORM_ROOT/harness/ACCEPTANCE.md.template"
    "$PLATFORM_ROOT/checklists/onboard-tenant.required.json"
    "$PLATFORM_ROOT/checklists/monitor-health.required.json"
    "$PLATFORM_ROOT/evals/tenant-agent/_fixed-safety-v1.yaml"
    "$PLATFORM_ROOT/evals/tenant-agent/generated/.gitkeep"
    "$PLATFORM_ROOT/evals/admin-agent/meta-eval-generation-v1.yaml"
    "$PLATFORM_ROOT/scripts/preflight-check.sh"
    "$PLATFORM_ROOT/scripts/validate-tenant-config.sh"
    "$PLATFORM_ROOT/scripts/analyze-reports.sh"
    "$PLATFORM_ROOT/scripts/eval-runner.sh"
    "$PLATFORM_ROOT/scripts/eval-judge.sh"
    "$PLATFORM_ROOT/scripts/_eval-check-single.sh"
    "$PLATFORM_ROOT/scripts/tenant/skill-verify.sh"
    "$PLATFORM_ROOT/incidents/all-tenants-no-connectivity.md"
    "$PLATFORM_ROOT/incidents/docker-version-rollback.md"
    "$PLATFORM_ROOT/incidents/telegram-api-change.md"
    "$PLATFORM_ROOT/incidents/mnemosyne-seed-corruption.md"
    "$PLATFORM_ROOT/incidents/platform-backup-recovery.md"
    "$PLATFORM_ROOT/skills/grill-me.md"
    "$PLATFORM_ROOT/skills/setup-admin-hermes.md"
    "$PLATFORM_ROOT/sop/build-image.md"
    "$PLATFORM_ROOT/sop/upgrade-platform.md"
    "$PLATFORM_ROOT/sop/onboard-tenant.md"
    "$PLATFORM_ROOT/sop/suspend-tenant.md"
    "$PLATFORM_ROOT/sop/reactivate-tenant.md"
    "$PLATFORM_ROOT/sop/offboard-tenant.md"
    "$PLATFORM_ROOT/sop/update-tenant.md"
    "$PLATFORM_ROOT/sop/upgrade-tenants.md"
    "$PLATFORM_ROOT/sop/monitor-health.md"
    "$PLATFORM_ROOT/sop/monitor-logs.md"
    "$PLATFORM_ROOT/sop/troubleshoot-tenant.md"
    "$PLATFORM_ROOT/sop/write-report.md"
    "$PLATFORM_ROOT/templates/_base/config.yaml.template"
    "$PLATFORM_ROOT/templates/_base/env.template"
    "$PLATFORM_ROOT/templates/_base/SOUL.md.template"
    "$PLATFORM_ROOT/templates/_base/USER.md.template"
    "$PLATFORM_ROOT/templates/_base/MEMORY.md.template"
    "$PLATFORM_ROOT/tenants.yaml"
    "$PLATFORM_ROOT/docker/docker-compose.yaml"
    "$PLATFORM_ROOT/reports/INDEX.jsonl"
  )

  for path in "${required[@]}"; do
    [ -f "$path" ] || error "Missing required file: $path"
  done

  grep -q "memory_enabled: false" "$PLATFORM_ROOT/templates/_base/config.yaml.template" \
    || error "Base config template must disable native Hermes memory"
  grep -q "provider: mnemosyne" "$PLATFORM_ROOT/templates/_base/config.yaml.template" \
    || error "Base config template must set memory.provider to mnemosyne"
  grep -q "home_chat_id: \"\"" "$PLATFORM_ROOT/templates/_base/config.yaml.template" \
    || error "Base config template must leave Telegram home_chat_id empty"
  grep -q "memory_enabled: false" "$PLATFORM_ROOT/admin-hermes/config.yaml.template" \
    || error "Hermes admin config template must disable native Hermes memory"
  grep -q "provider: mnemosyne" "$PLATFORM_ROOT/admin-hermes/config.yaml.template" \
    || error "Hermes admin config template must set memory.provider to mnemosyne"
  grep -q "MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data" "$PLATFORM_ROOT/admin-hermes/env.template" \
    || error "Hermes admin env template must keep Mnemosyne data inside the admin profile"
  grep -q "TELEGRAM_ALLOWED_USERS=" "$PLATFORM_ROOT/templates/_base/env.template" \
    || error "Base env template must document TELEGRAM_ALLOWED_USERS"
  grep -q "MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data" "$PLATFORM_ROOT/templates/_base/env.template" \
    || error "Base env template must keep Mnemosyne data inside /opt/data"
  grep -q "FROM nousresearch/hermes-agent:latest" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must extend nousresearch/hermes-agent:latest"
  grep -q "mnemosyne-memory\[embeddings\]" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must install mnemosyne-memory with embeddings"
  grep -q "mnemosyne-hermes" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must install mnemosyne-hermes"
  grep -q "^services:" "$PLATFORM_ROOT/docker/docker-compose.yaml" \
    || error "docker-compose.yaml must contain a top-level services mapping"
  grep -q "docker compose up -d {service-name}" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must include the service-specific docker compose safety rule"
  grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$PLATFORM_ROOT/VERSION" \
    || error "VERSION must contain a semantic version like 0.1.0"
  grep -q "sudo chown -R 10000:10000" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must set tenant volume ownership for Hermes UID 10000"
  grep -q "sudo chown -R 10000:10000" "$PLATFORM_ROOT/sop/update-tenant.md" \
    || error "Update tenant SOP must repair tenant volume ownership after edits"
  grep -q "sudo chown -R 10000:10000" "$PLATFORM_ROOT/sop/upgrade-tenants.md" \
    || error "Upgrade tenants SOP must repair tenant volume ownership after edits"
  grep -q "tenant_harness_owner_is_10000" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify harness.yaml ownership"
  grep -q "compose_has_restart_policy" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify tenant compose restart policy"
  grep -q "compose_has_memory_limit" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify tenant compose memory limit"
  grep -q "compose_has_cpu_limit" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify tenant compose CPU limit"
  grep -q "acceptance_owner_is_10000" "$PLATFORM_ROOT/scripts/validate-tenant-config.sh" \
    || error "Tenant config validator must verify ACCEPTANCE.md ownership"
  grep -q "HERMES_HOME=/opt/data" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must install mnemosyne-hermes via HERMES_HOME env var"
  grep -q "mnemosyne store" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must seed Mnemosyne with the store command"
  grep -q "chat not found" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must document Telegram chat-not-found handling"
  grep -q "Always write a task report" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must require task reports after SOP execution"
  grep -q "check-tenant.sh" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must advertise tenant harness checks"
  grep -q "tenant-harness.yaml.template" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must create tenant harness manifests"
  grep -q "_fixed-safety-v1.yaml" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must reference the fixed tenant eval profile"
  grep -q "tenant_harness_version: 1" "$PLATFORM_ROOT/harness/tenant-harness.yaml.template" \
    || error "Tenant harness manifest template must declare version 1"
  grep -q "verified_at_utc" "$PLATFORM_ROOT/harness/ACCEPTANCE.md.template" \
    || error "Tenant acceptance template must include verification timestamp"
  grep -q "confirms_before_posting" "$PLATFORM_ROOT/evals/tenant-agent/_fixed-safety-v1.yaml" \
    || error "Fixed tenant eval profile must verify confirmation-before-posting"
  grep -q "preflight-check.sh" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must advertise platform pre-flight checks"
  grep -q "validate-tenant-config.sh" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must validate tenant config"
  grep -q "restart: unless-stopped" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must require tenant compose restart policy"
  grep -q "mem_limit: 1g" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must document tenant compose resource limits"
  grep -q "troubleshoot-tenant" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must advertise tenant troubleshooting SOP"
  grep -q "AaaS pre-flight check" "$PLATFORM_ROOT/scripts/preflight-check.sh" \
    || error "Pre-flight script must contain expected banner"
  grep -q "INDEX.jsonl" "$PLATFORM_ROOT/sop/write-report.md" \
    || error "Report SOP must document AI-readable INDEX.jsonl"
  grep -q "directly under /opt/aaas/platform/reports" "$PLATFORM_ROOT/sop/write-report.md" \
    || error "Report SOP must forbid nested report category folders"
  grep -q "What This Must Preserve" "$PLATFORM_ROOT/sop/upgrade-platform.md" \
    || error "Platform upgrade SOP must document preserved files"
  validate_installed_matches_source

  success "Platform validation passed"
}

echo ""
echo "=============================================="
echo "  AaaS Platform - Platform Setup"
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
echo -e "  ${GREEN}Platform setup complete${NC}"
echo "=============================================="
echo ""
echo "Installed platform version: $(cat "$PLATFORM_ROOT/VERSION")"
echo ""
echo "Next steps:"
echo "  1. cd /opt/aaas/platform"
echo "  2. opencode"
echo "  3. Ask: what skills do you have available?"
echo "  4. When ready, build the image with:"
echo "       curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --build-image"
echo ""
