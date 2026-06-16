# Plan 0: Prerequisites & Bootstrap
> **AaaS Platform — One-Time Manual Setup**
> Version: 1.4
> Last Updated: 2026-06-16
> Status: Living document — improve as you learn

---

## Overview

This is a **one-time manual setup** done inside your WSL2 Ubuntu environment.
Once complete, OpenCode takes over all ongoing operations.

**Assumptions:**
- WSL2 is already installed on Windows
- Ubuntu distro is already created and running
- You are running commands from inside Ubuntu terminal

**Sequence:**
```
Plan 0 (this document)  →  Plan A (OpenCode setup)  →  Plan B (Hermes tenant setup)
```

---

## What the Setup Script Covers

```
✅ Windows PATH isolation  — disables appendWindowsPath in /etc/wsl.conf
✅ Ubuntu package updates
✅ Native WSL2 git (guards against Windows git leaking in via PATH)
✅ SSH key generation (ed25519) for later Git integration
✅ Node.js + npm installed natively in WSL2 via nvm
✅ Docker Engine installation inside WSL2
✅ OpenCode installation (uses WSL-native npm — not Windows npm)
✅ /opt/aaas/ folder structure creation
✅ tenants.yaml initialisation
✅ docker-compose.yaml initialisation

❌ WSL2 installation        (Windows-level, out of scope)
❌ Ubuntu distro creation   (Windows-level, out of scope)
❌ .wslconfig tuning        (Windows-level, out of scope)
❌ Hermes binary install    (runs inside Docker, not on host)
```

> **Why disable appendWindowsPath?**
> By default WSL2 injects the entire Windows `PATH` into every Linux
> session. This means Windows-installed tools (`node`, `npm`, `git`,
> `python`) appear in WSL as `/mnt/c/...` entries and can shadow or
> conflict with their native Linux counterparts. Setting
> `appendWindowsPath = false` in `/etc/wsl.conf` stops this entirely.
> The script also scrubs `/mnt/c` entries from the current session
> immediately so the rest of setup runs clean without needing a restart —
> but a `wsl --shutdown` is still required afterward for the setting to
> persist across future sessions.

> **Why nvm (not apt node)?**
> The apt `nodejs` package is often outdated. nvm installs the current
> LTS release natively in WSL, placing it in `~/.nvm/...` which appears
> in PATH before any Windows entries. If Windows also had Node.js
> installed, nvm ensures the WSL-native binary always wins.

---

## Quick Setup (Recommended)

Download and run the setup script in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/aaas-platform/main/setup.sh | bash
```

Or if you have the script locally:

```bash
chmod +x setup.sh
./setup.sh
```

The script is idempotent — safe to run multiple times.

---

## Manual Steps (if you prefer step-by-step)

### Step 0: Isolate WSL2 from Windows PATH

The script checks if `appendWindowsPath = false` is already set and skips if so.
Otherwise it creates or patches `/etc/wsl.conf` — it will not overwrite an existing
file but will add or update only the `[interop]` block.

It also immediately scrubs `/mnt/c` entries from the current session PATH so the
rest of setup runs against WSL-native binaries without requiring a restart.

To do this manually:

```bash
# If /etc/wsl.conf does not exist yet:
sudo tee /etc/wsl.conf > /dev/null << 'EOF'
[interop]
appendWindowsPath = false
EOF
```

If `/etc/wsl.conf` already exists with other settings, add only the `[interop]`
block rather than overwriting the whole file.

Scrub Windows PATH entries from the current session immediately:

```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^/mnt/c" | tr '\n' ':' | sed 's/:$//')
```

**Then restart WSL from PowerShell for the wsl.conf change to persist:**
```powershell
wsl --shutdown
```

Then reopen your Ubuntu terminal and verify:
```bash
echo $PATH | tr ':' '\n' | grep /mnt/c
# should return nothing
```

> If you need to access a specific Windows tool from WSL in future (e.g.
> `explorer.exe` or `code`), add it explicitly to your `~/.bashrc` PATH
> rather than re-enabling `appendWindowsPath`.

### Step 1: Update Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

```bash
sudo apt install -y curl git unzip build-essential openssh-client
```

### Step 2: Verify native WSL2 Git

Check git doesn't resolve to Windows:

```bash
which git
```

If the output contains `/mnt/c/`, force the WSL-native one:

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

### Step 4: Install Node.js natively in WSL2 via nvm

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

Verify WSL-native binaries (must NOT contain `/mnt/c/`):

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

Configure Docker to start automatically on WSL2 launch:

```bash
cat >> ~/.bashrc << 'EOF'

# Start Docker on WSL2 launch
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

### Step 6: Install OpenCode

> **nvm must be loaded** (from Step 4) before running this — it ensures
> the installer picks up WSL-native npm, not Windows npm.

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

Confirm opencode is a WSL binary (output must NOT contain `/mnt/c/`):

```bash
which opencode
```

> If opencode is found but points to `/mnt/c/...` (a previously installed Windows
> version), the script reinstalls it via `npm install -g opencode-ai` using the
> nvm-managed npm. Manual fix if this persists:
> ```powershell
> # In Windows PowerShell:
> npm uninstall -g opencode-ai
> ```
> Then re-run the script.

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
# Managed by OpenCode admin agent
# Add one service block per tenant
# Always specify service name when running docker compose commands
# to avoid affecting ALL tenants unintentionally

services: {}
EOF
```

### Step 10: Verify Everything

```bash
git --version
node --version && which node   # must NOT be /mnt/c/...
npm --version  && which npm    # must NOT be /mnt/c/...
docker --version
opencode --version && which opencode  # must NOT be /mnt/c/...
cat ~/.ssh/id_ed25519.pub
find /opt/aaas -type d
```

---

## Validation Checklist

Before proceeding to Plan A:

- [ ] `/etc/wsl.conf` contains `appendWindowsPath = false`
- [ ] WSL restarted (`wsl --shutdown` from PowerShell) and reopened
- [ ] `echo $PATH | tr ':' '\n' | grep /mnt/c` returns nothing
- [ ] `git --version` returns WSL-native git (not `/mnt/c/...`)
- [ ] Git identity configured (`git config --global user.name` and `user.email`)
- [ ] `cat ~/.ssh/id_ed25519.pub` prints your public key
- [ ] SSH public key added to GitHub/GitLab
- [ ] `which node` returns a path under `~/.nvm/` (not `/mnt/c/...`)
- [ ] `which npm` returns a path under `~/.nvm/` (not `/mnt/c/...`)
- [ ] `docker --version` returns successfully
- [ ] `docker run hello-world` runs successfully
- [ ] `opencode --version` returns successfully
- [ ] `which opencode` does NOT contain `/mnt/c/`
- [ ] `/opt/aaas/` folder structure created correctly
- [ ] `/opt/aaas/platform/tenants.yaml` initialised
- [ ] `/opt/aaas/platform/docker/docker-compose.yaml` initialised

---

## Troubleshooting

**Windows npm/node still showing up after nvm install:**
```bash
# Check PATH ordering — nvm dirs must come before /mnt/c/...
echo $PATH | tr ':' '\n' | head -20
# Load nvm explicitly and re-check
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
which npm
```

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

Proceed to **Plan A: OpenCode Admin Agent Setup**.