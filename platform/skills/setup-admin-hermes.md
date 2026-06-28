---
name: setup-admin-hermes
description: Install and configure Hermes as an optional admin agent after the default OpenCode platform setup. Use when the operator wants Hermes dashboard/admin support.
---

Set up the optional Hermes admin agent for the AaaS platform.

The base installer is OpenCode-first. Do not rerun platform setup with runtime flags. Hermes admin setup is an operator-requested add-on that uses the managed templates in `/opt/aaas/platform/admin-hermes`.

## Preconditions

- Platform root exists at `/opt/aaas/platform`.
- Managed templates exist under `/opt/aaas/platform/admin-hermes`.
- Python 3 and `python3-venv` are available.
- Never print, log, or store API keys or dashboard passwords in task reports.

## Ask The Operator

Collect these values before writing files:

1. Model provider.
   Recommended: `opencode`.
2. Model name.
   Recommended: `opencode/big-pickle`.
3. API key for the selected provider.
   Recommended: store only in `/opt/aaas/platform/admin/.env`.
4. Dashboard host.
   Recommended: `127.0.0.1`.
5. Dashboard port.
   Recommended: `9119`.
6. Whether to configure dashboard basic auth.
   Recommended: yes if the dashboard will bind anywhere other than `127.0.0.1`.

## Install Runtime

Install Hermes into an isolated admin venv:

```bash
python3 -m venv "$HOME/.local/share/aaas/hermes-admin-venv"
"$HOME/.local/share/aaas/hermes-admin-venv/bin/python" -m pip install --upgrade pip
"$HOME/.local/share/aaas/hermes-admin-venv/bin/python" -m pip install --upgrade 'hermes-agent[web,pty]' 'mnemosyne-memory[embeddings]' mnemosyne-hermes
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.local/share/aaas/hermes-admin-venv/bin/hermes" "$HOME/.local/bin/hermes"
```

Ensure `$HOME/.local/bin` is on `PATH`. If needed, add this block to `~/.bashrc` once:

```bash
# AaaS Hermes admin tools
export PATH="$HOME/.local/bin:$PATH"
```

## Create Admin Profile

Create `/opt/aaas/platform/admin` from templates. Preserve existing files unless the operator explicitly confirms overwrite.

Copy only missing files by default:

- `/opt/aaas/platform/admin-hermes/SOUL.md.template` to `/opt/aaas/platform/admin/SOUL.md`
- `/opt/aaas/platform/admin-hermes/USER.md.template` to `/opt/aaas/platform/admin/USER.md`
- `/opt/aaas/platform/admin-hermes/MEMORY.md.template` to `/opt/aaas/platform/admin/MEMORY.md`
- `/opt/aaas/platform/admin-hermes/config.yaml.template` to `/opt/aaas/platform/admin/config.yaml`
- `/opt/aaas/platform/admin-hermes/env.template` to `/opt/aaas/platform/admin/.env`

Create Mnemosyne storage:

```bash
mkdir -p /opt/aaas/platform/admin/mnemosyne/data
chmod 700 /opt/aaas/platform/admin
chmod 600 /opt/aaas/platform/admin/.env
```

## Configure Files

Update `/opt/aaas/platform/admin/config.yaml`:

```yaml
model:
  provider: {model-provider}
  default: {model-name}

memory:
  provider: mnemosyne
  memory_enabled: false
  user_profile_enabled: false

dashboard:
  host: {dashboard-host}
  port: {dashboard-port}
```

Update `/opt/aaas/platform/admin/.env`:

```bash
HERMES_HOME=/opt/aaas/platform/admin
MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data
```

Set the selected provider key only. Examples:

- OpenRouter: `OPENROUTER_API_KEY=...`
- OpenAI: `OPENAI_API_KEY=...`
- Anthropic: `ANTHROPIC_API_KEY=...`
- Nous: `NOUS_API_KEY=...`
- OpenCode Zen: `OPENCODE_API_KEY=...`

If basic auth is enabled, set:

```bash
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=...
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=...
HERMES_DASHBOARD_BASIC_AUTH_SECRET=...
```

## Validate

Run:

```bash
command -v hermes
hermes --version
test -f /opt/aaas/platform/admin/SOUL.md
test -f /opt/aaas/platform/admin/USER.md
test -f /opt/aaas/platform/admin/MEMORY.md
test -f /opt/aaas/platform/admin/config.yaml
test -f /opt/aaas/platform/admin/.env
grep -q "provider: mnemosyne" /opt/aaas/platform/admin/config.yaml
grep -q "memory_enabled: false" /opt/aaas/platform/admin/config.yaml
```

## Start Hermes

Tell the operator:

```bash
cd /opt/aaas/platform/admin
set -a; . ./.env; set +a
hermes dashboard --no-open
```

Default dashboard URL:

```text
http://127.0.0.1:9119
```

## Reporting

Write a task report using `/opt/aaas/platform/sop/write-report.md`.

The report may include provider name, model name, dashboard host, dashboard port, files created, and validation status. It must not include API keys, passwords, tokens, or auth secrets.