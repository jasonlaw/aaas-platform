# Prerequisites & Bootstrap
> **AaaS Platform — One-Time Manual Setup**
> Platform version is tracked in `platform/VERSION`
> Last Updated: 2026-06-16
> Status: Living document — improve as you learn

---

## Overview

This is a **one-time manual setup** done inside your Ubuntu/Linux environment.
Once complete, OpenCode takes over all ongoing platform operations.

**Assumptions:**
- Ubuntu/Linux is already installed and running
- You are running commands from a Linux terminal
- Your user has sudo access

**Sequence:**
```
Prerequisites -> Platform setup -> Hermes tenant reference and validation
```

---

## What the Setup Script Covers

```
✅ Ubuntu package updates
✅ Git installation and identity bootstrap
✅ SSH key generation (ed25519) for later Git integration
✅ Node.js + npm installed via nvm
✅ Docker Engine installation
✅ OpenCode admin agent installation
✅ /opt/aaas/ folder structure creation
✅ tenants.yaml initialisation
✅ docker-compose.yaml initialisation

❌ Hermes binary install    (runs inside Docker, not on host)
```

> **Why nvm (not apt node)?**
> The apt `nodejs` package is often outdated. nvm installs the current
> LTS release under `~/.nvm/...` and keeps Node.js independent from the
> system package manager.

---

## Quick Setup (Recommended)

Download and run the setup script from the actual repository in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup-prerequisites.sh | bash
```

Or if you have the script locally:

```bash
git clone https://github.com/jasonlaw/aaas-platform.git
cd aaas-platform
chmod +x scripts/setup-prerequisites.sh
./scripts/setup-prerequisites.sh
```

The script is idempotent — safe to run multiple times.

---

## Manual Steps (if you prefer step-by-step)

### Step 1: Update Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

```bash
sudo apt install -y curl git unzip build-essential openssh-client
```

### Step 2: Verify Git

Check git is installed:

```bash
which git
```

If the command is missing, install it:

```bash
sudo apt install -y git
```

Set your git identity (required for commits):

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@yourdomain.com"
```

> The script sets placeholder values (`you@example.com` / `AaaS Operator`) if
> no git identity is configured, and warns you to update them afterward.

### Step 3: Generate SSH key for Git

```bash
ssh-keygen -t ed25519 -C "aaas-platform-$(hostname)" -f ~/.ssh/id_ed25519 -N ""
```

Add your SSH agent auto-start to `~/.bashrc`:

```bash
cat >> ~/.bashrc << 'EOF'

# SSH agent auto-start (AaaS)
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null 2>&1
  ssh-add ~/.ssh/id_ed25519 > /dev/null 2>&1
fi
EOF
```

Print your public key — you'll need to add this to GitHub/GitLab:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the output and add it to:
- **GitHub**: Settings → SSH and GPG keys → New SSH key
- **GitLab**: Preferences → SSH Keys → Add new key

### Step 4: Install Node.js via nvm

> **Important:** Do NOT use `apt install nodejs` — the apt version is
> often outdated. Use nvm to get a current LTS release.

Install nvm (resolves the latest release automatically):

```bash
NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') \
  || NVM_LATEST="v0.40.1"
[ -z "$NVM_LATEST" ] && NVM_LATEST="v0.40.1"
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
```

Load nvm into the current session (the installer adds this to `~/.bashrc` but
it is not active until you reload):

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

Install and activate LTS Node:

```bash
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'
```

Verify Node.js and npm:

```bash
which node && node --version
which npm  && npm --version
```

### Step 5: Install Docker Engine

```bash
curl -fsSL https://get.docker.com | sh
```

```bash
sudo usermod -aG docker $USER
```

```bash
newgrp docker
```

Configure Docker to start automatically for interactive shells:

```bash
cat >> ~/.bashrc << 'EOF'

# Start Docker service (AaaS)
if sudo service docker status 2>&1 | grep -q "not running"; then
  sudo service docker start > /dev/null 2>&1
fi
EOF
```

```bash
source ~/.bashrc
```

Verify Docker works:

```bash
docker --version
docker run hello-world
```

> `newgrp docker` and `docker run hello-world` are manual verification steps —
> the script starts Docker with `sudo service docker start` and verifies with
> `docker --version` only. Run `docker run hello-world` manually to confirm
> end-to-end functionality.

### Step 6: Install OpenCode Admin Agent

> **nvm must be loaded** (from Step 4) before running this so npm-based
> installs use the nvm-managed Node.js.

```bash
curl -fsSL https://opencode.ai/install | bash
```

After install, explicitly add the known install locations to PATH for the current
session (the installer writes to `~/.bashrc` but this doesn't activate until the
next shell):

```bash
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
```

Verify:

```bash
opencode --version
```

Confirm opencode is on PATH:

```bash
which opencode
```

### Step 7: Create Platform Folder Structure

```bash
sudo mkdir -p /opt/aaas/platform/sop
sudo mkdir -p /opt/aaas/platform/templates/_base
sudo mkdir -p /opt/aaas/platform/templates/verticals/fnb
sudo mkdir -p /opt/aaas/platform/templates/verticals/retail
sudo mkdir -p /opt/aaas/platform/templates/verticals/services
sudo mkdir -p /opt/aaas/platform/docker
sudo mkdir -p /opt/aaas/tenants
```

```bash
sudo chown -R "$USER":"$USER" /opt/aaas
```

### Step 8: Initialise Tenant Registry

```bash
cat > /opt/aaas/platform/tenants.yaml << 'EOF'
# AaaS Platform — Tenant Registry
# Business metadata only — secrets live in per-tenant .env files
# Container management is in docker-compose.yaml
# Status values: active | suspended | offboarded

tenants: []
EOF
```

### Step 9: Create Empty Docker Compose File

```bash
cat > /opt/aaas/platform/docker/docker-compose.yaml << 'EOF'
# AaaS Platform — Tenant Container Registry
# Managed by the AaaS admin agent
# The admin agent adds one service block per tenant under services:
# Always specify service name when running docker compose commands
# to avoid affecting ALL tenants unintentionally

services:
  # Tenant services are added here by the admin agent during onboarding.
EOF
```

### Step 10: Verify Everything

```bash
git --version
node --version && which node
npm --version  && which npm
docker --version
opencode --version && which opencode
cat ~/.ssh/id_ed25519.pub
find /opt/aaas -type d
```

---

## Validation Checklist

Before proceeding to Platform setup:

- [ ] `git --version` returns successfully
- [ ] Git identity configured (`git config --global user.name` and `user.email`)
- [ ] `cat ~/.ssh/id_ed25519.pub` prints your public key
- [ ] SSH public key added to GitHub/GitLab
- [ ] `which node` returns a path under `~/.nvm/`
- [ ] `which npm` returns a path under `~/.nvm/`
- [ ] `docker --version` returns successfully
- [ ] `docker run hello-world` runs successfully
- [ ] `opencode --version` returns successfully
- [ ] `which opencode` returns successfully
- [ ] `/opt/aaas/` folder structure created correctly
- [ ] `/opt/aaas/platform/tenants.yaml` initialised
- [ ] `/opt/aaas/platform/docker/docker-compose.yaml` initialised

---

## Troubleshooting

**nvm command not found after install:**
```bash
# Source nvm directly instead of relying on ~/.bashrc reload
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
command -v nvm
```

**Docker permission denied:**
```bash
sudo usermod -aG docker $USER && newgrp docker
```

**OpenCode not found after install:**
```bash
# Explicitly add install locations to PATH for the current session
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
which opencode
```

**OpenCode install fails:**
```bash
curl -fsSL https://opencode.ai/install -o install.sh
chmod +x install.sh
./install.sh
```

**Permission denied creating /opt/aaas:**
```bash
sudo mkdir -p /opt/aaas && sudo chown -R "$USER":"$USER" /opt/aaas
```

**SSH key not loading on new terminal:**
```bash
# Ensure this is in your ~/.bashrc:
grep -A4 "SSH agent" ~/.bashrc
```

---

## Next Step

Proceed to **Platform Setup**:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```
