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
  sudo usermod -aG docker $USER
  success "Docker installed"
fi

# Start Docker service
sudo service docker start > /dev/null 2>&1 || true

# Add Docker auto-start to .bashrc (idempotent check)
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
# Step 6: Install OpenCode admin agent
# nvm is loaded above, so npm-based installs use the nvm-managed Node.js.
# ------------------------------------------------------------------------------
log "Step 6: Installing OpenCode admin agent..."
install_opencode

# ------------------------------------------------------------------------------
# Step 7: Create Platform Folder Structure
# ------------------------------------------------------------------------------
log "Step 7: Creating platform folder structure..."

sudo mkdir -p /opt/aaas/platform/sop
sudo mkdir -p /opt/aaas/platform/skills
sudo mkdir -p /opt/aaas/platform/reports
sudo mkdir -p /opt/aaas/platform/backups
sudo mkdir -p /opt/aaas/platform/templates/_base
sudo mkdir -p /opt/aaas/platform/templates/verticals/fnb
sudo mkdir -p /opt/aaas/platform/templates/verticals/retail
sudo mkdir -p /opt/aaas/platform/templates/verticals/services
sudo mkdir -p /opt/aaas/platform/docker
sudo mkdir -p /opt/aaas/tenants
sudo chown -R "$USER":"$USER" /opt/aaas

if [ ! -f /opt/aaas/platform/reports/INDEX.jsonl ]; then
  touch /opt/aaas/platform/reports/INDEX.jsonl
fi

success "Folder structure created at /opt/aaas/"

# ------------------------------------------------------------------------------
# Step 8: Initialise Tenant Registry
# ------------------------------------------------------------------------------
log "Step 8: Initialising tenant registry..."

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
# Step 9: Initialise Docker Compose File
# ------------------------------------------------------------------------------
log "Step 9: Initialising docker-compose.yaml..."

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
echo "git:       $(git --version)"
echo "node:      $(node --version)  ($(which node))"
echo "npm:       $(npm --version)   ($(which npm))"
echo "docker:    $(docker --version)"
echo "opencode:  $(opencode --version)"
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
echo "  3. Run 'source ~/.bashrc' or open a new terminal"
echo "     to activate nvm, Docker auto-start, and SSH agent."
echo ""
echo "  4. Proceed with the main setup entrypoint"
echo "       curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash"
echo ""
echo "     Or force a Hermes tenant image build:"
echo "       curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --build-image"
echo ""
