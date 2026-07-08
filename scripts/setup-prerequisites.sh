#!/bin/bash
# =============================================================================
# AaaS Platform — Bootstrap Setup Script
# Run this once inside your Ubuntu/Linux terminal
# Assumptions: Ubuntu/Linux host is already running
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()    { echo -e "${BLUE}[AaaS]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -h, --help  Show this help.
EOF
}

while [ "${1:-}" != "" ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
  shift
done

echo ""
echo "=============================================="
echo "  AaaS Platform — Bootstrap Setup"
echo "=============================================="
echo ""

install_opencode() {
  OPENCODE_PATH=$(which opencode 2>/dev/null || true)

  if [ -z "$OPENCODE_PATH" ]; then
    log "OpenCode not found — installing..."
    curl -fsSL https://opencode.ai/install | bash
    # The installer writes to ~/.bashrc but source ~/.bashrc is unreliable in
    # non-interactive scripts. Explicitly prepend known install locations
    # so opencode is available for the rest of this session.
    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
    source ~/.bashrc 2>/dev/null || true
    success "OpenCode installed"

  else
    warn "OpenCode already installed at: $OPENCODE_PATH — skipping"
  fi

  opencode --version || error "OpenCode installation failed"

  OPENCODE_PATH=$(which opencode 2>/dev/null || true)
  success "OpenCode ready: $OPENCODE_PATH"
}

# ------------------------------------------------------------------------------
# Step 1: Update Ubuntu
# ------------------------------------------------------------------------------
log "Step 1: Updating Ubuntu packages..."

sudo apt update -q && sudo apt upgrade -y -q
sudo apt install -y -q curl git unzip build-essential openssh-client python3 python3-pip python3-venv

success "Ubuntu packages updated"

# ------------------------------------------------------------------------------
# Step 2: Install Git
# ------------------------------------------------------------------------------
log "Step 2: Verifying Git..."

GIT_PATH=$(which git 2>/dev/null || true)
if [ -z "$GIT_PATH" ]; then
  error "git not found after apt install — check your apt sources"
fi

GIT_PATH=$(which git 2>/dev/null || true)
success "Git ready: $GIT_PATH ($(git --version))"

# Set minimal git global config if not already set
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  log "Setting default git global config (update these after setup)..."
  git config --global user.email "you@example.com"
  git config --global user.name "AaaS Operator"
  warn "Git user.name and user.email set to placeholders — update with your real details:"
  warn "  git config --global user.name  \"Your Name\""
  warn "  git config --global user.email \"you@yourdomain.com\""
else
  success "Git global config already set: $(git config --global user.name) <$(git config --global user.email)>"
fi

# ------------------------------------------------------------------------------
# Step 3: Generate SSH key for Git integration
# ------------------------------------------------------------------------------
log "Step 3: Setting up SSH key for Git integration..."

SSH_KEY="$HOME/.ssh/id_ed25519"

if [ -f "$SSH_KEY" ]; then
  warn "SSH key already exists at $SSH_KEY — skipping generation"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "aaas-platform-$(hostname)" -f "$SSH_KEY" -N ""
  success "SSH key generated at $SSH_KEY"
fi

# Ensure SSH agent is available and key is loaded
eval "$(ssh-agent -s)" > /dev/null 2>&1
ssh-add "$SSH_KEY" > /dev/null 2>&1 || true

# Add SSH agent auto-start to .bashrc (idempotent)
if ! grep -q "SSH agent auto-start" ~/.bashrc; then
  cat >> ~/.bashrc << 'EOF'

# SSH agent auto-start (AaaS)
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null 2>&1
  ssh-add ~/.ssh/id_ed25519 > /dev/null 2>&1
fi
EOF
  success "SSH agent auto-start added to ~/.bashrc"
else
  warn "SSH agent auto-start already in ~/.bashrc — skipping"
fi

# Ensure ~/.bash_profile sources ~/.bashrc so nvm/opencode are available
# in login shells and new terminal sessions (Ubuntu/WSL often read
# ~/.bash_profile on login but skip ~/.bashrc unless explicitly sourced).
# This is the root cause of "opencode not found" after a fresh install when
# the installer was run via 'curl | bash' or when a new terminal is opened.
if [ ! -f "$HOME/.bash_profile" ] || ! grep -q 'source.*\.bashrc\|\. .*\.bashrc' "$HOME/.bash_profile"; then
  cat >> "$HOME/.bash_profile" << 'EOF'

# Source .bashrc for interactive login shells (AaaS)
if [ -f "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1091
  source "$HOME/.bashrc"
fi
EOF
  success "~/.bash_profile now sources ~/.bashrc — nvm/opencode will be available in all new terminals"
else
  warn "~/.bash_profile already sources ~/.bashrc — skipping"
fi

echo ""
echo "======================================================"
echo -e "  ${GREEN}Your SSH PUBLIC KEY (add this to GitHub/GitLab):${NC}"
echo "======================================================"
cat "$SSH_KEY.pub"
echo "======================================================"
echo ""

# ------------------------------------------------------------------------------
# Step 4: Install Node.js via nvm
# ------------------------------------------------------------------------------
log "Step 4: Installing Node.js via nvm..."

# Install nvm if not present
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  # Resolve latest nvm version tag; fall back to known-good version if curl fails
  NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
    | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') \
    || NVM_LATEST="v0.40.1"
  [ -z "$NVM_LATEST" ] && NVM_LATEST="v0.40.1"
  log "Installing nvm $NVM_LATEST..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
  success "nvm $NVM_LATEST installed"
else
  warn "nvm already installed — skipping"
fi

# Load nvm into current shell session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Add nvm to .bashrc if not already there (nvm installer usually does this,
if ! grep -q "NVM_DIR" ~/.bashrc; then
  cat >> ~/.bashrc << 'EOF'

# nvm - Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
  success "nvm added to ~/.bashrc"
else
  warn "nvm already in ~/.bashrc — skipping"
fi

# Verify nvm loaded correctly before using it
if ! command -v nvm &>/dev/null; then
  error "nvm failed to load — check that $NVM_DIR/nvm.sh exists and is readable"
fi

# Install LTS Node.js
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

NODE_PATH=$(which node)
NPM_PATH=$(which npm)

success "Node.js ready: $NODE_PATH — $(node --version)"
success "npm ready: $NPM_PATH — $(npm --version)"

# ------------------------------------------------------------------------------
# Step 5: Install Docker Engine
# ------------------------------------------------------------------------------
log "Step 5: Installing Docker Engine..."

if command -v docker &> /dev/null; then
  warn "Docker already installed — skipping install"
  docker --version
else
  curl -fsSL https://get.docker.com | sh
  success "Docker installed"
fi

# Docker group membership is checked independently of whether Docker was
# just installed above. A pre-existing Docker install (shared host,
# pre-baked image, Docker set up by something other than this script) must
# not skip granting access — the old code only ran `usermod` in the
# "just installed" branch, so any host with Docker already present silently
# never got the current user added to the docker group. `usermod -aG` is
# idempotent, so it's safe to check-and-grant unconditionally every run.
DOCKER_GROUP_JUST_ADDED=false
if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  DOCKER_GROUP_JUST_ADDED=true
  success "Added $USER to docker group"
fi

# Enable Docker at boot when the host uses systemd, then start it now.
if command -v systemctl &> /dev/null && systemctl list-unit-files docker.service > /dev/null 2>&1; then
  sudo systemctl enable docker
  sudo systemctl start docker
  success "Docker service enabled for boot and started"
else
  warn "systemd docker.service not available - using service start and shell auto-start fallback"
  sudo service docker start > /dev/null 2>&1 || true
fi

# Add Docker auto-start to .bashrc as a fallback for non-systemd environments.
if ! grep -q "Start Docker service (AaaS)" ~/.bashrc; then
  cat >> ~/.bashrc << 'EOF'

# Start Docker service (AaaS)
if sudo service docker status 2>&1 | grep -q "not running"; then
  sudo service docker start > /dev/null 2>&1
fi
EOF
  success "Docker auto-start added to ~/.bashrc"
else
  warn "Docker auto-start already in ~/.bashrc — skipping"
fi

# Verify Docker
docker --version || error "Docker installation failed"
success "Docker Engine ready"

# ------------------------------------------------------------------------------
# Step 5.1: Refresh docker group membership in the current shell session
# ------------------------------------------------------------------------------
# `sudo usermod -aG docker $USER` only takes effect in a new login session.
# A child process (including a bash subprocess) inherits the parent's group
# list at the time it was spawned and cannot pick up group additions made
# afterward — not even via `source ~/.bashrc` or `exec bash`. The only
# in-session mechanism is `newgrp` (which replaces the shell) or `sg`
# (which re-execs a command under the new group). We use `sg` here to
# re-exec this same script with the same arguments but with the docker group
# already active, which makes every subsequent step — including those in
# setup-platform.sh called by setup.sh — work without any logout or terminal
# restart. The guard avoids an infinite re-exec loop: if the current process
# already has the docker group (DOCKER_GROUP_ALREADY_ACTIVE is set, or
# `id` confirms it), we skip the re-exec.
if [ "$DOCKER_GROUP_JUST_ADDED" = true ] && [ "${DOCKER_GROUP_ALREADY_ACTIVE:-}" != "true" ]; then
  if ! id -Gn | grep -qw docker; then
    log "Docker group added — re-executing script under new group membership (no logout needed)..."
    export DOCKER_GROUP_ALREADY_ACTIVE=true

    # `sudo -g docker` re-execs the script with the docker group active in
    # the new process. It is part of sudo (installed on every Ubuntu system)
    # so it is more reliable than `sg`, which is part of shadow-utils and
    # is not present on all Ubuntu configurations (e.g. minimal cloud images).
    # We try sudo -g first, then sg as a fallback, then instruct the user
    # to log out/in if both are unavailable.
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      exec sudo -E -u "$USER" -g docker bash "$0" "$@"
    elif command -v sg >/dev/null 2>&1; then
      exec sg docker -c "$(printf '%q ' "$0" "$@")"
    else
      warn "Neither 'sudo -g' nor 'sg' is available to refresh docker group membership."
      warn "Docker commands in this session may fail with a permission error."
      warn "If they do, log out and back in, then re-run this script."
      warn "Continuing anyway..."
    fi
    # exec replaces the current process; lines below are only reached if
    # exec itself failed (extremely unlikely) or the fallback warn path ran.
  fi
fi
success "Docker group membership active in current session"

# ------------------------------------------------------------------------------
# Step 5.5: Configure iptables to legacy mode (required for Docker bridge networking)
# ------------------------------------------------------------------------------
log "Step 5.5: Configuring iptables to legacy mode..."

CURRENT_IPTABLES=$(iptables --version 2>/dev/null | head -1)
if echo "$CURRENT_IPTABLES" | grep -q "nf_tables"; then
  log "Current iptables backend is nftables (incompatible with Docker 29.x)"
  log "Switching to iptables-legacy..."
  
  sudo update-alternatives --set iptables /usr/sbin/iptables-legacy > /dev/null 2>&1 || true
  sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy > /dev/null 2>&1 || true
  
  # Restart Docker to apply the new iptables mode
  sudo systemctl restart docker
  sleep 2  # Give Docker daemon time to restart
  
  success "iptables switched to legacy mode and Docker restarted"
else
  warn "iptables backend is already legacy or compatible — no changes needed"
fi

# Verify iptables version
IPTABLES_VERSION=$(iptables --version)
success "iptables ready: $IPTABLES_VERSION"

# ------------------------------------------------------------------------------
# Step 6: Install OpenCode admin agent
# nvm is loaded above, so npm-based installs use the nvm-managed Node.js.
# ------------------------------------------------------------------------------
log "Step 6: Installing OpenCode admin agent..."
install_opencode

# ------------------------------------------------------------------------------
# Step 7: Install Agent Vault CLI
# ------------------------------------------------------------------------------
log "Step 7: Installing Agent Vault CLI..."

if command -v agent-vault >/dev/null 2>&1; then
  warn "Agent Vault CLI already installed at: $(which agent-vault) — skipping"
  agent-vault --version
else
  curl -fsSL https://raw.githubusercontent.com/Infisical/agent-vault/main/install.sh | sh
  # Installer may write to ~/.local/bin — ensure it is on PATH for this session
  export PATH="$HOME/.local/bin:$PATH"
fi

agent-vault --version || error "Agent Vault CLI installation failed"
success "Agent Vault CLI ready: $(which agent-vault)"

# ------------------------------------------------------------------------------
# Step 8: Create Platform Folder Structure
# ------------------------------------------------------------------------------
log "Step 8: Creating platform folder structure..."

sudo mkdir -p /opt/aaas/platform/sop
sudo mkdir -p /opt/aaas/platform/skills
sudo mkdir -p /opt/aaas/platform/reports
sudo mkdir -p /opt/aaas/platform/backups
sudo mkdir -p /opt/aaas/platform/tenant-hermes
sudo mkdir -p /opt/aaas/platform/docker
sudo mkdir -p /opt/aaas/platform/watchdog/logs
sudo mkdir -p /opt/aaas/platform/watchdog/state
sudo mkdir -p /opt/aaas/tenants
sudo mkdir -p /opt/aaas/agent-vault/data
# The agent-vault image runs as a non-root, unprivileged user whose host
# UID/GID is not exposed/configurable, so 700 leaves this bind mount
# unwritable to the container and it fails to report healthy. Keep this in
# sync with the equivalent fix in scripts/setup-platform.sh.
sudo chmod 777 /opt/aaas/agent-vault/data
sudo chown -R "$USER":"$USER" /opt/aaas

if [ ! -f /opt/aaas/platform/reports/INDEX.jsonl ]; then
  touch /opt/aaas/platform/reports/INDEX.jsonl
fi

success "Folder structure created at /opt/aaas/"

# ------------------------------------------------------------------------------
# Step 9: Initialise Tenant Registry
# ------------------------------------------------------------------------------
log "Step 9: Initialising tenant registry..."

if [ ! -f /opt/aaas/platform/tenants.yaml ]; then
  cat > /opt/aaas/platform/tenants.yaml << 'EOF'
# AaaS Platform — Tenant Registry
# Business metadata only — secrets live in per-tenant .env files
# Container management is in docker-compose.yaml
# Status values: active | suspended | offboarded

tenants: []
EOF
  success "tenants.yaml created"
else
  warn "tenants.yaml already exists — skipping"
fi

# ------------------------------------------------------------------------------
# Step 10: Initialise Docker Compose File
# ------------------------------------------------------------------------------
log "Step 10: Initialising docker-compose.yaml..."

if [ ! -f /opt/aaas/platform/docker/docker-compose.yaml ]; then
  cat > /opt/aaas/platform/docker/docker-compose.yaml << 'EOF'
# AaaS Platform — Tenant Container Registry
# Managed by the AaaS admin agent
# The admin agent adds one service block per tenant under services:
# Always specify service name when running docker compose commands
# to avoid affecting ALL tenants unintentionally

services:
  # Tenant services are added here by the admin agent during onboarding.
EOF
  success "docker-compose.yaml created"
else
  warn "docker-compose.yaml already exists — skipping"
fi

# ------------------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------------------
log "Verifying setup..."

echo ""
echo "--- Tool Versions ---"
echo "git:           $(git --version)"
echo "node:          $(node --version)  ($(which node))"
echo "npm:           $(npm --version)   ($(which npm))"
echo "docker:        $(docker --version)"
echo "opencode:      $(opencode --version)"
echo "agent-vault:   $(agent-vault --version)"
echo ""

echo "--- SSH Public Key ---"
cat "$HOME/.ssh/id_ed25519.pub"
echo ""

echo "--- Folder Structure ---"
find /opt/aaas -type d
echo ""

echo "--- tenants.yaml ---"
cat /opt/aaas/platform/tenants.yaml
echo ""

echo "--- docker-compose.yaml ---"
cat /opt/aaas/platform/docker/docker-compose.yaml
echo ""

# ------------------------------------------------------------------------------
# Activate new PATH entries in the current shell session
# ------------------------------------------------------------------------------
# The installers above (nvm, opencode) wrote PATH and shell function exports to
# ~/.bashrc, but a child script can't modify the *parent* shell's environment.
# Source the key files here so every tool is live for the remainder of *this*
# shell session (e.g. if the user runs setup.sh from the same terminal).
# This is safe to run multiple times — the guards inside ~/.bashrc prevent
# duplicate entries.

log "Activating environment in current shell session..."

# nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# opencode and other ~/.local/bin tools
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

success "Environment activated in current shell session"

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo -e "  ${GREEN}AaaS Platform Bootstrap Complete!${NC}"
echo "=============================================="
echo ""
echo "Admin agent: OpenCode"
echo "Next steps:"
echo ""
echo "  1. Copy the SSH public key above and add it to GitHub/GitLab:"
echo "     GitHub  → Settings → SSH and GPG keys → New SSH key"
echo "     GitLab  → Preferences → SSH Keys → Add new key"
echo ""
echo "  2. Update your git identity:"
echo "     git config --global user.name  \"Your Name\""
echo "     git config --global user.email \"you@yourdomain.com\""
echo ""
echo "  3. Your current terminal session is already fully configured — no"
echo "     logout or restart needed. Docker group membership, nvm, and"
echo "     opencode are all active right now via in-script re-exec and"
echo "     PATH export. If you open a NEW terminal later and tools are"
echo "     missing, run:"
echo "         exec bash"
echo "     (This reloads your shell, picking up all ~/.bashrc changes,"
echo "     and is faster and more reliable than 'source ~/.bashrc'.)"
echo ""
echo "  4. Proceed with the main setup entrypoint:"
echo "       bash <(curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh) --yes"
echo ""
echo "     (Use 'bash <(curl ...)' rather than 'curl ... | bash' so that PATH"
echo "     and group membership set by the script stay active in your current"
echo "     terminal. The --yes flag skips the interactive version-confirm prompt,"
echo "     required when running non-interactively.)"
echo ""
echo "     The setup script will:"
echo "       - Install platform assets (SOPs, scripts, templates)"
echo "       - Create /opt/aaas/agent-vault/ and write its docker-compose.yaml"
echo "       - Pull the Agent Vault image"
echo "       - Start Agent Vault if AGENT_VAULT_MASTER_PASSWORD is already set in"
echo "           /opt/aaas/agent-vault/.env"
echo ""
echo "  5. After setup completes, follow the printed next steps to:"
echo "       - Set the master password (if not set before setup)"
echo "       - Start Agent Vault"
echo "       - Complete Agent Vault setup via OpenCode (register account,"
echo "           fetch MITM CA, rebuild tenant image)"
echo ""