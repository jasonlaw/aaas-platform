---
name: setup-admin-hermes
description: >
  Step 2 of platform setup. Install and configure Hermes as the admin agent,
  with its LLM API key secured through Agent Vault (same policy as tenants).
  Run this after OpenCode setup and Agent Vault are both operational.
  Required before enabling the bidirectional channel.
---

# Skill: Setup Admin Hermes

**Prerequisite:** OpenCode platform setup is complete and Agent Vault is
running and healthy. Verify before starting:

    /opt/aaas/platform/scripts/agent-vault-health.sh
    # Expected: all PASS

If Agent Vault is not healthy, follow /opt/aaas/platform/sop/setup-agent-vault.md
first. Do not proceed until it passes.

## Preconditions

- Platform root exists at /opt/aaas/platform
- Managed templates exist under /opt/aaas/platform/admin-hermes
- Agent Vault is running and healthy (verified above)
- agent-vault CLI authenticated: agent-vault vault list must succeed
- Python 3 and python3-venv are available
- Never print, log, or store API keys or passwords in task reports

## Ask The Operator

Collect before writing any files. Never write the real API key anywhere
except Agent Vault (Step 5).

1. LLM provider and model. Recommended: openrouter / openai/gpt-4.1-mini
2. Real LLM API key — stored in Agent Vault only, never in .env
3. Dashboard host. Recommended: 127.0.0.1
4. Dashboard port. Recommended: 9119
5. Dashboard basic auth? Recommended: yes if binding outside localhost

## Step 1 — Install Runtime

    python3 -m venv "$HOME/.local/share/aaas/hermes-admin-venv"
    "$HOME/.local/share/aaas/hermes-admin-venv/bin/python" -m pip install --upgrade pip
    "$HOME/.local/share/aaas/hermes-admin-venv/bin/python" -m pip install --upgrade 'hermes-agent[web,pty]' 'mnemosyne-memory[embeddings]' mnemosyne-hermes
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HOME/.local/share/aaas/hermes-admin-venv/bin/hermes" "$HOME/.local/bin/hermes"

Ensure $HOME/.local/bin is on PATH. Add to ~/.bashrc if missing:
    export PATH="$HOME/.local/bin:$PATH"

## Step 2 — Create Admin Profile

    mkdir -p /opt/aaas/platform/admin

Copy only missing files (never overwrite without operator confirmation):
- admin-hermes/SOUL.md.template  -> admin/SOUL.md
- admin-hermes/USER.md.template  -> admin/USER.md
- admin-hermes/MEMORY.md.template -> admin/MEMORY.md
- admin-hermes/config.yaml.template -> admin/config.yaml
- admin-hermes/env.template -> admin/.env

    mkdir -p /opt/aaas/platform/admin/mnemosyne/data
    chmod 700 /opt/aaas/platform/admin
    chmod 600 /opt/aaas/platform/admin/.env

## Step 3 — Configure Files

Update /opt/aaas/platform/admin/config.yaml with provider, model, dashboard
values. Leave .env untouched until Step 5 — real API key must never be
written into .env.

## Step 4 — Install Agent Vault CA on Host

Admin Hermes runs on the host (not in Docker). It needs the Agent Vault MITM
CA in the host system trust store.

    sudo cp /opt/aaas/platform/docker/agent-vault-ca.pem \
      /usr/local/share/ca-certificates/agent-vault-ca.crt
    sudo update-ca-certificates

Verify:
    openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
      /usr/local/share/ca-certificates/agent-vault-ca.crt 2>/dev/null \
      && echo "CA trusted on host" || echo "FAIL: CA not trusted"

If agent-vault-ca.pem is missing, re-run step 3 of
/opt/aaas/platform/sop/setup-agent-vault.md to fetch it, then retry.

## Step 5 — Provision Admin Vault

The real API key is stored in Agent Vault only. .env holds only the
placeholder. Same policy as every tenant — no exceptions for the admin agent.

### 5.1 Create the admin vault

    agent-vault vault create admin-vault
    # Skip if admin-vault already exists

### 5.2 Provider hostname reference

| Provider     | Hostname              | Env var               |
|--------------|-----------------------|-----------------------|
| OpenRouter   | openrouter.ai         | OPENROUTER_API_KEY    |
| OpenAI       | api.openai.com        | OPENAI_API_KEY        |
| Anthropic    | api.anthropic.com     | ANTHROPIC_API_KEY     |
| Nous         | api.nous.ai           | NOUS_API_KEY          |
| OpenCode Zen | opencode.ai           | OPENCODE_API_KEY      |

### 5.3 Store the credential and register the service

    agent-vault vault credential set {PROVIDER_VAR}={real-api-key} --vault admin-vault

    agent-vault vault service add \
      --vault admin-vault \
      --name {PROVIDER_VAR} \
      --host {hostname} \
      --auth-type Bearer \
      --token-key {PROVIDER_VAR}

Real key is now in Agent Vault only. Do not write it anywhere else.

### 5.4 Mint an agent token

    ADMIN_VAULT_TOKEN=$(agent-vault agent create \
      --vault admin-vault:proxy \
      --name hermes_admin \
      --token-only)

### 5.5 Set placeholder and inject proxy config

Admin Hermes runs on the host — proxy address is localhost:14322, not the
Docker container hostname used by tenant containers.

    PROVIDER_VAR={PROVIDER_VAR}
    sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" \
      /opt/aaas/platform/admin/.env

    cat >> /opt/aaas/platform/admin/.env <<PROXYEOF

    # Agent Vault proxy — injected by setup-admin-hermes
    # Admin Hermes runs on the host; proxy is localhost:14322.
    HTTP_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322
    HTTPS_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322
    NO_PROXY=localhost,127.0.0.1
    AGENT_VAULT_TOKEN=${ADMIN_VAULT_TOKEN}
    AGENT_VAULT_VAULT=admin-vault
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    PROXYEOF

### 5.6 Verify the real key is gone — both checks must pass

    # Check 1: placeholder must be present
    grep -qx "${PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/platform/admin/.env \
      && echo "OK: placeholder set" \
      || echo "FAIL: real key not scrubbed"

    # Check 2: no live key pattern remaining
    grep -E "(sk-[A-Za-z0-9_-]{10,}|sk-ant-|sk-or-v1-)" /opt/aaas/platform/admin/.env
    # Expected: no output. Any match is a live key — remove manually before continuing.

If either check fails, stop. Remove the real key manually and re-run Step 5.5.

## Step 6 — Validate Installation

    command -v hermes && hermes --version
    test -f /opt/aaas/platform/admin/SOUL.md     && echo "OK: SOUL.md"
    test -f /opt/aaas/platform/admin/USER.md     && echo "OK: USER.md"
    test -f /opt/aaas/platform/admin/MEMORY.md   && echo "OK: MEMORY.md"
    test -f /opt/aaas/platform/admin/config.yaml && echo "OK: config.yaml"
    test -f /opt/aaas/platform/admin/.env        && echo "OK: .env"
    grep -q "provider: mnemosyne"    /opt/aaas/platform/admin/config.yaml && echo "OK: mnemosyne"
    grep -q "memory_enabled: false"  /opt/aaas/platform/admin/config.yaml && echo "OK: memory disabled"
    grep -q "routed-via-agent-vault" /opt/aaas/platform/admin/.env        && echo "OK: placeholder"
    grep -q "HTTP_PROXY"             /opt/aaas/platform/admin/.env        && echo "OK: proxy config"
    grep -q "SSL_CERT_FILE"          /opt/aaas/platform/admin/.env        && echo "OK: SSL_CERT_FILE"
    agent-vault vault credential list --vault admin-vault
    agent-vault vault service list --vault admin-vault
    agent-vault agent list --vault admin-vault

## Step 7 — Start Hermes and Verify Proxy

    cd /opt/aaas/platform/admin
    set -a; . ./.env; set +a
    hermes dashboard --no-open

In a second terminal, confirm the proxy intercepts LLM calls:

    cd /opt/aaas/platform/admin
    set -a; . ./.env; set +a
    hermes -z "Reply with the single word: PROXY_OK"

Expected: a response containing PROXY_OK. If the call fails with a proxy or
SSL error, re-check Step 4 (CA trust) and Step 5 (proxy vars in .env).

## Step 8 — Install Watchdog

    /opt/aaas/platform/scripts/hermes-admin-watchdog.sh --install

Verify:
    systemctl --user status hermes-admin-watchdog.timer
    # Expected: active (waiting)

See /opt/aaas/platform/incidents/hermes-admin-failure.md for the recovery
playbook OpenCode uses when the watchdog detects Hermes admin is down.

## Reporting

Write a task report using /opt/aaas/platform/sop/write-report.md.

Include: provider name, model name, dashboard host/port, files created, vault
name, agent token name (hermes_admin), CA trust status, proxy verification
result, watchdog install status.

Never include: API keys, vault tokens, passwords, auth secrets, or any
credential-shaped value.
