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
    "$ASSET_ROOT/policy/platform-policy.yaml"
    "$ASSET_ROOT/tenant-hermes/evals/_fixed-safety-v1.yaml"
    "$ASSET_ROOT/tenant-hermes/evals/generated/.gitkeep"
    "$ASSET_ROOT/evals/meta-eval-generation-v1.yaml"
    "$ASSET_ROOT/scripts/preflight-check.sh"
    "$ASSET_ROOT/scripts/validate-tenant-config.sh"
    "$ASSET_ROOT/scripts/generate-platform-eval.sh"
    "$ASSET_ROOT/scripts/validate-platform-rules.sh"
    "$ASSET_ROOT/scripts/analyze-reports.sh"
    "$ASSET_ROOT/scripts/eval-runner.sh"
    "$ASSET_ROOT/scripts/eval-judge.sh"
    "$ASSET_ROOT/scripts/_eval-check-single.sh"
    "$ASSET_ROOT/tenant-hermes/scripts/skill-verify.sh"
    "$ASSET_ROOT/tenant-hermes/scripts/vault-init-tenant.sh"
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
    "$ASSET_ROOT/sop/setup-agent-vault.md"
    "$ASSET_ROOT/sop/provision-tenant-vault.md"
    "$ASSET_ROOT/sop/deprovision-tenant-vault.md"
    "$ASSET_ROOT/sop/sync-knowledge-vault.md"
    "$ASSET_ROOT/skills/query-knowledge-vault.md"
    "$ASSET_ROOT/scripts/vault-init.sh"
    "$ASSET_ROOT/scripts/agent-vault-health.sh"
    "$ASSET_ROOT/incidents/agent-vault-failure.md"
    "$ASSET_ROOT/tenant-hermes/config.yaml.template"
    "$ASSET_ROOT/tenant-hermes/env.template"
    "$ASSET_ROOT/tenant-hermes/SOUL.md.template"
    "$ASSET_ROOT/tenant-hermes/USER.md.template"
    "$ASSET_ROOT/tenant-hermes/MEMORY.md.template"
    "$ASSET_ROOT/tenant-hermes/policy/tenant-policy.yaml.template"
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
    "tenant-hermes/evals/_fixed-safety-v1.yaml"
    "tenant-hermes/evals/generated/.gitkeep"
    "evals/meta-eval-generation-v1.yaml"
    "scripts/preflight-check.sh"
    "scripts/validate-tenant-config.sh"
    "scripts/analyze-reports.sh"
    "scripts/eval-runner.sh"
    "scripts/eval-judge.sh"
    "scripts/_eval-check-single.sh"
    "tenant-hermes/scripts/skill-verify.sh"
    "tenant-hermes/scripts/vault-init-tenant.sh"
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
    "sop/setup-agent-vault.md"
    "sop/provision-tenant-vault.md"
    "sop/deprovision-tenant-vault.md"
    "sop/sync-knowledge-vault.md"
    "skills/query-knowledge-vault.md"
    "scripts/vault-init.sh"
    "scripts/agent-vault-health.sh"
    "incidents/agent-vault-failure.md"
    "tenant-hermes/config.yaml.template"
    "tenant-hermes/env.template"
    "tenant-hermes/SOUL.md.template"
    "tenant-hermes/USER.md.template"
    "tenant-hermes/MEMORY.md.template"
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
    "policy"
    "evals"
    "incidents"
    "sop"
    "skills"
    "tenant-hermes"
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
  command -v agent-vault >/dev/null 2>&1 || error "agent-vault CLI not found. Run scripts/setup-prerequisites.sh first."
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
  mkdir -p "$PLATFORM_ROOT/tenant-hermes"
  mkdir -p "$PLATFORM_ROOT/docker"
  mkdir -p "$PLATFORM_ROOT/admin-hermes"
  mkdir -p "$PLATFORM_ROOT/harness"
  mkdir -p "$PLATFORM_ROOT/checklists"
  mkdir -p "$PLATFORM_ROOT/policy"
  mkdir -p "$PLATFORM_ROOT/evals"
  mkdir -p "$PLATFORM_ROOT/incidents"
  mkdir -p "$PLATFORM_ROOT/scripts"
  mkdir -p "$PLATFORM_ROOT/vault"
  mkdir -p "$INSTALL_ROOT/tenants"

  if [ "$BACKUP_BEFORE_INSTALL" = true ]; then
    backup_managed_assets
  else
    warn "Skipping managed asset backup for this install"
  fi

  copy_tree "$ASSET_ROOT/sop" "$PLATFORM_ROOT/sop"
  copy_tree "$ASSET_ROOT/skills" "$PLATFORM_ROOT/skills"
  copy_tree "$ASSET_ROOT/tenant-hermes" "$PLATFORM_ROOT/tenant-hermes"
  copy_tree "$ASSET_ROOT/admin-hermes" "$PLATFORM_ROOT/admin-hermes"
  copy_tree "$ASSET_ROOT/harness" "$PLATFORM_ROOT/harness"
  copy_tree "$ASSET_ROOT/checklists" "$PLATFORM_ROOT/checklists"
  copy_tree "$ASSET_ROOT/policy" "$PLATFORM_ROOT/policy"
  copy_tree "$ASSET_ROOT/evals" "$PLATFORM_ROOT/evals"
  copy_tree "$ASSET_ROOT/incidents" "$PLATFORM_ROOT/incidents"
  copy_tree "$ASSET_ROOT/scripts" "$PLATFORM_ROOT/scripts"
  chmod +x "$PLATFORM_ROOT/harness/check-tenant.sh"
  chmod +x "$PLATFORM_ROOT/scripts/preflight-check.sh"
  chmod +x "$PLATFORM_ROOT/scripts/validate-tenant-config.sh"
  chmod +x "$PLATFORM_ROOT/scripts/analyze-reports.sh"
  chmod +x "$PLATFORM_ROOT/scripts/eval-runner.sh"
  chmod +x "$PLATFORM_ROOT/scripts/eval-judge.sh"
  chmod +x "$PLATFORM_ROOT/scripts/_eval-check-single.sh"
  chmod +x "$PLATFORM_ROOT/tenant-hermes/scripts/skill-verify.sh"
  chmod +x "$PLATFORM_ROOT/tenant-hermes/scripts/vault-init-tenant.sh"
  chmod +x "$PLATFORM_ROOT/scripts/agent-vault-health.sh"
  chmod +x "$PLATFORM_ROOT/scripts/vault-init.sh"
  chmod +x "$PLATFORM_ROOT/scripts/generate-platform-eval.sh"
  chmod +x "$PLATFORM_ROOT/scripts/validate-platform-rules.sh"
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

setup_agent_vault() {
  local vault_root="$INSTALL_ROOT/agent-vault"
  local vault_data="$vault_root/data"
  local vault_compose="$vault_root/docker-compose.yaml"
  local vault_env="$vault_root/.env"

  log "Setting up Agent Vault infrastructure..."

  # --- Directory ---
  if [ ! -d "$vault_data" ]; then
    mkdir -p "$vault_data"
    # The agent-vault image runs as a non-root, unprivileged user whose host
    # UID/GID is not exposed/configurable. 700 leaves the bind mount
    # unwritable to that user and the container fails to start healthy.
    # 770 is not sufficient either, since the container's UID is not a
    # member of any host group we control. Until the image exposes a
    # configurable UID (or a PUID/PGID-style entrypoint), this directory
    # must stay world-writable for the container to initialise its database.
    chmod 777 "$vault_data"
    success "Created Agent Vault data directory: $vault_data"
  else
    warn "Agent Vault data directory already exists — leaving it unchanged"
  fi

  # --- Compose file (own file, peer to platform/) ---
  if [ ! -f "$vault_compose" ]; then
    cat > "$vault_compose" <<'EOF'
# Agent Vault — AaaS credential broker
# Managed independently of the tenant Compose file.
# Start/stop with: docker compose -f /opt/aaas/agent-vault/docker-compose.yaml up -d
# Tenant containers join agent-vault-net (declared external: true in the tenant Compose file).

services:
  agent-vault:
    image: infisical/agent-vault:latest
    container_name: agent-vault
    ports:
      - "127.0.0.1:14321:14321"
      - "127.0.0.1:14322:14322"
    volumes:
      - /opt/aaas/agent-vault/data:/data
    env_file:
      - /opt/aaas/agent-vault/.env
    environment:
      - AGENT_VAULT_ADDR=http://localhost:14321
      - AGENT_VAULT_ALLOW_PRIVATE_RANGES=true
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:14321/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - agent-vault-net

networks:
  agent-vault-net:
    name: agent-vault-net
    driver: bridge
    internal: false
EOF
    success "Created Agent Vault docker-compose.yaml: $vault_compose"
  else
    warn "Agent Vault docker-compose.yaml already exists — leaving it unchanged"
  fi

  # --- .env stub (master password — never overwrite) ---
  if [ ! -f "$vault_env" ]; then
    cat > "$vault_env" <<'EOF'
# Agent Vault master password — DO NOT COMMIT THIS FILE
# Fill in AGENT_VAULT_MASTER_PASSWORD before starting Agent Vault.
# Loss of this password requires a vault reset and re-entry of all credentials.
AGENT_VAULT_MASTER_PASSWORD=
EOF
    chmod 600 "$vault_env"
    success "Created Agent Vault .env stub: $vault_env"
    warn "ACTION REQUIRED: Set AGENT_VAULT_MASTER_PASSWORD in $vault_env before starting Agent Vault"
  else
    warn "Agent Vault .env already exists — leaving it unchanged (master password preserved)"
  fi

  # --- Pull image ---
  log "Pulling Agent Vault image..."
  docker pull infisical/agent-vault:latest
  success "Agent Vault image ready"

  # --- Start container if master password is set ---
  if grep -q "^AGENT_VAULT_MASTER_PASSWORD=.\+" "$vault_env" 2>/dev/null; then
    log "Starting Agent Vault container..."
    docker compose -f "$vault_compose" up -d agent-vault
    # Wait up to 30s for healthy
    local i=0
    while [ $i -lt 6 ]; do
      HEALTH="$(docker inspect --format='{{.State.Health.Status}}' agent-vault 2>/dev/null || echo 'unknown')"
      [ "$HEALTH" = "healthy" ] && break
      sleep 5
      i=$((i + 1))
    done
    HEALTH="$(docker inspect --format='{{.State.Health.Status}}' agent-vault 2>/dev/null || echo 'unknown')"
    if [ "$HEALTH" = "healthy" ]; then
      success "Agent Vault container is healthy"
    else
      warn "Agent Vault container health status: $HEALTH — check logs with: docker logs agent-vault --tail 30"
    fi
  else
    warn "AGENT_VAULT_MASTER_PASSWORD is not set in $vault_env"
    warn "Agent Vault container NOT started. Set the password, then run:"
    warn "  docker compose -f $vault_compose up -d agent-vault"
    warn "Then complete setup by following: /opt/aaas/platform/sop/setup-agent-vault.md"
  fi

  success "Agent Vault infrastructure setup complete"
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
    "$PLATFORM_ROOT/tenant-hermes/evals/_fixed-safety-v1.yaml"
    "$PLATFORM_ROOT/tenant-hermes/evals/generated/.gitkeep"
    "$PLATFORM_ROOT/evals/meta-eval-generation-v1.yaml"
    "$PLATFORM_ROOT/scripts/preflight-check.sh"
    "$PLATFORM_ROOT/scripts/validate-tenant-config.sh"
    "$PLATFORM_ROOT/scripts/analyze-reports.sh"
    "$PLATFORM_ROOT/scripts/eval-runner.sh"
    "$PLATFORM_ROOT/scripts/eval-judge.sh"
    "$PLATFORM_ROOT/scripts/_eval-check-single.sh"
    "$PLATFORM_ROOT/tenant-hermes/scripts/skill-verify.sh"
    "$PLATFORM_ROOT/tenant-hermes/scripts/vault-init-tenant.sh"
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
    "$PLATFORM_ROOT/sop/setup-agent-vault.md"
    "$PLATFORM_ROOT/sop/provision-tenant-vault.md"
    "$PLATFORM_ROOT/sop/deprovision-tenant-vault.md"
    "$PLATFORM_ROOT/sop/sync-knowledge-vault.md"
    "$PLATFORM_ROOT/skills/query-knowledge-vault.md"
    "$PLATFORM_ROOT/scripts/vault-init.sh"
    "$PLATFORM_ROOT/scripts/agent-vault-health.sh"
    "$PLATFORM_ROOT/incidents/agent-vault-failure.md"
    "$PLATFORM_ROOT/tenant-hermes/config.yaml.template"
    "$PLATFORM_ROOT/tenant-hermes/env.template"
    "$PLATFORM_ROOT/tenant-hermes/SOUL.md.template"
    "$PLATFORM_ROOT/tenant-hermes/USER.md.template"
    "$PLATFORM_ROOT/tenant-hermes/MEMORY.md.template"
    "$PLATFORM_ROOT/tenants.yaml"
    "$PLATFORM_ROOT/docker/docker-compose.yaml"
    "$PLATFORM_ROOT/reports/INDEX.jsonl"
  )

  for path in "${required[@]}"; do
    [ -f "$path" ] || error "Missing required file: $path"
  done

  grep -q "memory_enabled: false" "$PLATFORM_ROOT/tenant-hermes/config.yaml.template" \
    || error "Base config template must disable native Hermes memory"
  grep -q "provider: mnemosyne" "$PLATFORM_ROOT/tenant-hermes/config.yaml.template" \
    || error "Base config template must set memory.provider to mnemosyne"
  grep -q "home_chat_id: \"\"" "$PLATFORM_ROOT/tenant-hermes/config.yaml.template" \
    || error "Base config template must leave Telegram home_chat_id empty"
  grep -q "memory_enabled: false" "$PLATFORM_ROOT/admin-hermes/config.yaml.template" \
    || error "Hermes admin config template must disable native Hermes memory"
  grep -q "provider: mnemosyne" "$PLATFORM_ROOT/admin-hermes/config.yaml.template" \
    || error "Hermes admin config template must set memory.provider to mnemosyne"
  grep -q "MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data" "$PLATFORM_ROOT/admin-hermes/env.template" \
    || error "Hermes admin env template must keep Mnemosyne data inside the admin profile"
  grep -q "TELEGRAM_ALLOWED_USERS=" "$PLATFORM_ROOT/tenant-hermes/env.template" \
    || error "Base env template must document TELEGRAM_ALLOWED_USERS"
  grep -q "MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data" "$PLATFORM_ROOT/tenant-hermes/env.template" \
    || error "Base env template must keep Mnemosyne data inside /opt/data"
  grep -q "FROM nousresearch/hermes-agent:latest" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must extend nousresearch/hermes-agent:latest"
  grep -q "mnemosyne-memory\[embeddings\]" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must install mnemosyne-memory with embeddings"
  grep -q "mnemosyne-hermes" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must install mnemosyne-hermes"
  grep -q "agent-vault-ca.crt" "$PLATFORM_ROOT/docker/Dockerfile" \
    || error "Dockerfile must include the Agent Vault MITM CA trust block (COPY agent-vault-ca.pem + update-ca-certificates)"
  [ -f "$PLATFORM_ROOT/docker/agent-vault-ca.pem" ] \
    || error "Agent Vault CA certificate missing: $PLATFORM_ROOT/docker/agent-vault-ca.pem — run the setup-agent-vault SOP step 3 to fetch it from the running Agent Vault container"
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
  grep -q "tenant_knowledge_vault_directory" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify the tenant knowledge vault directory exists"
  grep -q "compose_mounts_tenant_vault" "$PLATFORM_ROOT/harness/check-tenant.sh" \
    || error "Tenant harness check must verify the tenant knowledge vault compose mount"
  grep -q "acceptance_owner_is_10000" "$PLATFORM_ROOT/scripts/validate-tenant-config.sh" \
    || error "Tenant config validator must verify ACCEPTANCE.md ownership"
  grep -q "knowledge_vault_owner_is_10000" "$PLATFORM_ROOT/scripts/validate-tenant-config.sh" \
    || error "Tenant config validator must verify the tenant knowledge vault ownership"
  grep -q "HERMES_HOME=/opt/data" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must install mnemosyne-hermes via HERMES_HOME env var"
  grep -q "mnemosyne store" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must seed Mnemosyne with the store command"
  grep -q "chat not found" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must document Telegram chat-not-found handling"
  grep -q "Always write a task report" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must require task reports after SOP execution"
  # The deployed admin/SOUL.md (not the template) is only created by the
  # separate setup-admin-hermes skill, not by this script — so it may
  # legitimately not exist yet on a fresh platform install. But once it
  # does exist, nothing else in this codebase ever re-syncs or content-checks
  # it (see upgrade-platform.md step 9.3), so re-running --validate-only
  # against an already-configured admin instance is the only automated
  # backstop against it silently drifting behind the shipped template.
  if [ -f "$PLATFORM_ROOT/admin/SOUL.md" ]; then
    grep -q "Always write a task report" "$PLATFORM_ROOT/admin/SOUL.md" \
      || error "Deployed admin/SOUL.md is missing the task report rule — it has drifted from admin-hermes/SOUL.md.template. Run upgrade-platform.md step 9.3 to diff and refresh it."
    grep -q "Agent Vault is for LLM API keys only" "$PLATFORM_ROOT/admin/SOUL.md" \
      || error "Deployed admin/SOUL.md is missing the credential/secret rules — it has drifted from admin-hermes/SOUL.md.template. Run upgrade-platform.md step 9.3 to diff and refresh it."
  fi
  grep -q "check-tenant.sh" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must advertise tenant harness checks"
  grep -q "vault/" "$PLATFORM_ROOT/AGENTS.md" \
    || error "AGENTS.md must document the knowledge vault path"
  grep -q "sync-knowledge-vault.md" "$PLATFORM_ROOT/sop/write-report.md" \
    || error "write-report SOP must point to the knowledge vault sync step"
  grep -q "vault-init-tenant.sh" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must scaffold the tenant knowledge vault"
  grep -q "/home/hermes/vault" "$PLATFORM_ROOT/tenant-hermes/SOUL.md.template" \
    || error "Tenant SOUL template must document the tenant knowledge vault path"
  grep -q "business-data.md" "$PLATFORM_ROOT/tenant-hermes/SOUL.md.template" \
    || error "Tenant SOUL template must distinguish the knowledge vault from business-data.md"
  grep -q "tenant-harness.yaml.template" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must create tenant harness manifests"
  grep -q "_fixed-safety-v1.yaml" "$PLATFORM_ROOT/sop/onboard-tenant.md" \
    || error "Onboarding SOP must reference the fixed tenant eval profile"
  grep -q "tenant_harness_version: 1" "$PLATFORM_ROOT/harness/tenant-harness.yaml.template" \
    || error "Tenant harness manifest template must declare version 1"
  grep -q "verified_at_utc" "$PLATFORM_ROOT/harness/ACCEPTANCE.md.template" \
    || error "Tenant acceptance template must include verification timestamp"
  grep -q "confirms_before_posting" "$PLATFORM_ROOT/tenant-hermes/evals/_fixed-safety-v1.yaml" \
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
  # Agent Vault infrastructure (runtime, not managed assets — existence checks only)
  [ -d "$INSTALL_ROOT/agent-vault/data" ] \
    || error "Agent Vault data directory missing: $INSTALL_ROOT/agent-vault/data — run setup-prerequisites.sh"
  [ -f "$INSTALL_ROOT/agent-vault/docker-compose.yaml" ] \
    || error "Agent Vault docker-compose.yaml missing: $INSTALL_ROOT/agent-vault/docker-compose.yaml"
  grep -q "^    name: agent-vault-net$" "$INSTALL_ROOT/agent-vault/docker-compose.yaml" 2>/dev/null \
    || error "Agent Vault docker-compose.yaml must pin the network to 'name: agent-vault-net' (otherwise Compose project-prefixes it and tenant containers fail to find it as an external network)"
  [ -f "$INSTALL_ROOT/agent-vault/.env" ] \
    || error "Agent Vault .env missing: $INSTALL_ROOT/agent-vault/.env"
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
  setup_agent_vault
  bash "$PLATFORM_ROOT/scripts/vault-init.sh" "$PLATFORM_ROOT/vault" \
    || warn "Knowledge vault scaffold step failed - run /opt/aaas/platform/scripts/vault-init.sh manually later"
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

VAULT_ENV="$INSTALL_ROOT/agent-vault/.env"
if grep -q "^AGENT_VAULT_MASTER_PASSWORD=.\+" "$VAULT_ENV" 2>/dev/null; then
  echo "Agent Vault: running (master password already set)"
  echo ""
  echo "Next steps:"
  echo "  1. cd /opt/aaas/platform && opencode"
  echo "  2. Ask the admin agent: \'Complete the Agent Vault setup\'"
  echo "     This registers the account, fetches the MITM CA, patches"
  echo "     the Dockerfile, and rebuilds the tenant image."
  echo "  3. Onboard your first tenant."
else
  echo "Agent Vault: NOT started — master password required"
  echo ""
  echo "Next steps:"
  echo "  1. Set the master password:"
  echo "       nano $VAULT_ENV"
  echo "     Fill in: AGENT_VAULT_MASTER_PASSWORD=<your-password>"
  echo ""
  echo "  2. Start Agent Vault:"
  echo "       docker compose -f $INSTALL_ROOT/agent-vault/docker-compose.yaml up -d agent-vault"
  echo ""
  echo "  3. cd /opt/aaas/platform && opencode"
  echo "  4. Ask the admin agent: \'Complete the Agent Vault setup\'"
  echo "     This registers the account, fetches the MITM CA, patches"
  echo "     the Dockerfile, and rebuilds the tenant image."
fi
echo ""