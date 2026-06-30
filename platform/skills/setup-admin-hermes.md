---
name: setup-admin-hermes
description: >
  Step 2 of platform setup. Install and configure Hermes as the admin agent,
  with its LLM API key secured through Agent Vault (same policy as tenants).
  Optionally configures a Telegram channel for the admin agent if the
  operator requests it. Run this after OpenCode setup and Agent Vault are
  both operational. Required before enabling the bidirectional channel.
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
- This skill runs as root (or via sudo). It creates and owns a dedicated
  `aaas` service account — Hermes admin is not tied to any individual
  operator's login account or $HOME.

## Ask The Operator

Collect before writing any files. Never write the real API key anywhere
except Agent Vault (Step 5).

1. LLM provider and model. Recommended: openrouter / openai/gpt-4.1-mini
2. Real LLM API key — stored in Agent Vault only, never in .env
3. Dashboard host. Recommended: 127.0.0.1
4. Dashboard port. Recommended: 9119
5. Dashboard basic auth? Recommended: yes if binding outside localhost
6. Enable Telegram for admin Hermes? If yes, also collect:
   - Telegram bot token (from @BotFather)
   - Allow list: numeric Telegram user IDs permitted to message this agent.
     Mandatory if Telegram is enabled — do not proceed to Step 3.1 with an
     empty allow list. If the operator gives none, stop and ask again; an
     enabled Telegram channel with no allowed users is not a valid state.
   - TELEGRAM_HOME_CHANNEL: which allowed user is the primary contact for
     proactive messages (alerts, restart notifications)? Set via .env, not
     config.yaml — see Step 3.1.
     - If the allow list has more than one ID, present them as options and
       ask the operator to choose.
     - If the allow list has exactly one ID, use it as the home channel
       automatically — no separate confirmation needed, since it's the
       only valid choice.

## Step 1 — Install Runtime

Create the dedicated service account that owns Hermes admin, if it doesn't
already exist. This keeps the agent independent of any individual
operator's login account:

    id -u aaas &>/dev/null || \
      sudo useradd --system --no-create-home --shell /usr/sbin/nologin aaas

Install the venv and binary under /opt/aaas, owned by aaas:

    sudo python3 -m venv /opt/aaas/hermes-admin-venv
    sudo /opt/aaas/hermes-admin-venv/bin/python -m pip install --upgrade pip
    sudo /opt/aaas/hermes-admin-venv/bin/python -m pip install --upgrade \
      'hermes-agent[web,pty]' 'mnemosyne-memory[embeddings]' mnemosyne-hermes
    sudo mkdir -p /opt/aaas/bin
    sudo ln -sf /opt/aaas/hermes-admin-venv/bin/hermes /opt/aaas/bin/hermes
    sudo chown -R aaas:aaas /opt/aaas/hermes-admin-venv /opt/aaas/bin

Add /opt/aaas/bin to the system PATH (not any one user's ~/.bashrc), e.g.
via /etc/profile.d/aaas.sh:

    echo 'export PATH="/opt/aaas/bin:$PATH"' | sudo tee /etc/profile.d/aaas.sh

**Known gap (unverified, not yet fixed here):** a field report from a live
setup additionally needed `dashboard_auth` (described as a `hermes-agent`
wheel packaging bug) and the `plugins/platforms/telegram/` adapter plus
`python-telegram-bot` v22.8 installed separately before Telegram would load
at all — on top of the `home_chat_id`/`HERMES_HOME` fixes in Step 3.1 above.
This skill's Step 1 install command was not changed to add these, because
the exact missing extra/dependency and whether it's universal or specific
to that environment could not be confirmed against `hermes-agent` source
from here. If Telegram fails to load with an import error for
`dashboard_auth` or a missing platform adapter after Step 1, check whether
`'hermes-agent[web,pty,telegram]'` (or similar) is the intended extras
syntax, and update this step once confirmed.

## Step 2 — Create Admin Profile

    mkdir -p /opt/aaas/platform/admin

Copy only missing files (never overwrite without operator confirmation):
- admin-hermes/SOUL.md.template  -> admin/SOUL.md
- admin-hermes/USER.md.template  -> admin/USER.md
- admin-hermes/MEMORY.md.template -> admin/MEMORY.md
- admin-hermes/config.yaml.template -> admin/config.yaml
- admin-hermes/env.template -> admin/.env

    mkdir -p /opt/aaas/platform/admin/mnemosyne/data
    chown -R aaas:aaas /opt/aaas/platform/admin
    chmod 700 /opt/aaas/platform/admin
    chmod 600 /opt/aaas/platform/admin/.env

## Step 3 — Configure Files

Update /opt/aaas/platform/admin/config.yaml with provider, model, dashboard
values. Leave .env untouched until Step 5 — real API key must never be
written into .env.

## Step 3.1 — Configure Telegram (optional)

Skip this step entirely if the operator declined Telegram in Ask The
Operator above. Leave the commented-out TELEGRAM_BOT_TOKEN /
TELEGRAM_ALLOWED_USERS lines in .env and the commented-out
gateway.platforms.telegram block in config.yaml as-is.

If the operator enabled Telegram, the allow list is mandatory — do not
continue with this step if it's empty. Go back to Ask The Operator and
collect at least one ID before writing anything.

1. Uncomment and fill in .env:

       TELEGRAM_BOT_TOKEN={token}
       TELEGRAM_ALLOWED_USERS={comma-separated numeric IDs}
       TELEGRAM_HOME_CHANNEL={selected-id}

   TELEGRAM_ALLOWED_USERS is the access control mechanism — anyone not on
   this list cannot reach the agent even if they somehow learn the home
   channel ID. TELEGRAM_HOME_CHANNEL only designates the primary contact
   for Hermes-initiated messages (alerts, restart notifications); it does
   not grant access by itself. This is the only place the home channel is
   actually configured — the gateway reads it via `_apply_env_overrides()`
   in `gateway/config.py`. It does **not** read any `home_chat_id` key from
   `config.yaml`; that key only exists in the template as inert
   documentation of the field tenant bots leave empty (see config.yaml.template
   comment). Do not rely on setting `home_chat_id` in `config.yaml` — it has
   no effect on routing.

2. Leave the gateway block in config.yaml as shipped (commented out, or
   uncommented with `home_chat_id` left empty) — there is nothing to fill
   in here for the home channel; `TELEGRAM_HOME_CHANNEL` in `.env` from
   step 1 is what actually configures it.

3. Verify the token format looks plausible (numeric bot ID, colon, token
   body) before writing it — do not write an empty or obviously malformed
   token. Never print the token value in any report or log.

4. The gateway must be started with `HERMES_HOME` exported to the process
   environment (`/opt/aaas/platform/admin`) or it falls back to `~/.hermes`,
   finds no config there, and silently starts with no messaging platforms
   enabled — no error, just "No messaging platforms enabled" in the gateway
   log. Step 7 below already does this; if Hermes is ever started by hand
   outside this skill, `HERMES_HOME` must be set first.

5. After Step 7 starts Hermes, send a test message to the configured
   TELEGRAM_HOME_CHANNEL value to verify delivery:

       curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d chat_id="${TELEGRAM_HOME_CHANNEL}" \
         --data-urlencode text="Admin Hermes Telegram channel is live."

   A `400 Bad Request: chat not found` or `403 Forbidden` means that user
   has not yet opened the bot and sent /start — this is expected for users
   who haven't initiated contact yet, not a setup failure. Note it in the
   task report rather than treating it as blocking.

6. Confirm in the gateway log that Telegram actually connected, not just
   that the process started — `HERMES_HOME` and `TELEGRAM_HOME_CHANNEL`
   misconfiguration both fail silently (no crash, no error), so absence
   of an error is not sufficient evidence:

       grep -i "Connected to Telegram\|No messaging platforms enabled" \
         /opt/aaas/platform/logs/hermes-admin.log | tail -5

   Expect "Connected to Telegram". If you instead see "No messaging
   platforms enabled", `HERMES_HOME` was not set when the process started
   — restart per Step 7 with `HERMES_HOME` exported first.

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
    grep -q "provider: mnemosyne"       /opt/aaas/platform/admin/config.yaml && echo "OK: mnemosyne"
    grep -q "memory_enabled: false"     /opt/aaas/platform/admin/config.yaml && echo "OK: memory disabled"
    grep -q "user_profile_enabled: false" /opt/aaas/platform/admin/config.yaml && echo "OK: user profile disabled"
    grep -q "routed-via-agent-vault" /opt/aaas/platform/admin/.env        && echo "OK: placeholder"
    grep -q "HTTP_PROXY"             /opt/aaas/platform/admin/.env        && echo "OK: proxy config"
    grep -q "SSL_CERT_FILE"          /opt/aaas/platform/admin/.env        && echo "OK: SSL_CERT_FILE"
    agent-vault vault credential list --vault admin-vault
    agent-vault vault service list --vault admin-vault
    agent-vault agent list --vault admin-vault

**Validate `SOUL.md` and `config.yaml` content, not just their existence.**
A bare `test -f` above only proves a file exists — it says nothing about
whether it still contains the rules and invariants the admin agent actually
has to follow. This matters because Step 2 copies both files from their
templates once and never touches them again; nothing elsewhere in this repo
re-syncs or content-checks the deployed copies, so a template that ships a
new or reworded rule after this admin instance was first set up will
silently never reach it unless these checks catch the drift. This already
happened once for real: `admin-hermes/config.yaml.template` gained a
Telegram `gateway` block in 0.13.1 and had a wrong comment corrected in
0.13.2 — any admin instance set up before either release kept the stale
file with nothing ever flagging it.

    grep -q "Always write a task report" /opt/aaas/platform/admin/SOUL.md \
      && echo "OK: report-writing rule present" \
      || echo "FAIL: admin SOUL.md is missing the task report rule — re-copy or merge admin-hermes/SOUL.md.template"
    grep -q "Agent Vault is for LLM API keys only" /opt/aaas/platform/admin/SOUL.md \
      && echo "OK: credential rules present" \
      || echo "FAIL: admin SOUL.md is missing the credential/secret rules — re-copy or merge admin-hermes/SOUL.md.template"
    grep -q "provider: mnemosyne" /opt/aaas/platform/admin/config.yaml \
      && echo "OK: config.yaml still uses mnemosyne" \
      || echo "FAIL: admin config.yaml no longer specifies the mnemosyne memory provider"
    grep -q "memory_enabled: false" /opt/aaas/platform/admin/config.yaml \
      && echo "OK: config.yaml still disables native memory" \
      || echo "FAIL: admin config.yaml no longer disables native Hermes memory — re-copy or merge admin-hermes/config.yaml.template"
    grep -q "user_profile_enabled: false" /opt/aaas/platform/admin/config.yaml \
      && echo "OK: config.yaml still disables native user profile" \
      || echo "FAIL: admin config.yaml no longer disables native Hermes user profile — re-copy or merge admin-hermes/config.yaml.template"

If any of these FAIL on a fresh install, Step 2/3 copied or edited a
corrupted template — stop and investigate before continuing. If any FAIL
during a re-run against an already-configured admin instance, see
`/opt/aaas/platform/sop/upgrade-platform.md` step 9.3, which diffs and offers
to refresh both `admin/SOUL.md` and `admin/config.yaml` against their current
templates; do not silently overwrite an operator-customized file here.

**Check `.env` for structurally new required keys, not just secret values.**
A future `env.template` may add a new non-secret key (the same way
`TELEGRAM_HOME_CHANNEL` was added in 0.13.1) that an already-configured
`.env` will never pick up on its own. This check only verifies key *names*
are present somewhere in the file (commented or not) — it never compares or
touches secret values, since real values legitimately differ from the
template by design:

    for key in $(grep -oE '^#?\s*[A-Za-z_]+=' /opt/aaas/platform/admin-hermes/env.template | sed -E 's/^#\s*//; s/=$//' | sort -u); do
      grep -q "^${key}=\|^# ${key}=" /opt/aaas/platform/admin/.env \
        && echo "OK: ${key} present" \
        || echo "FAIL: ${key} is in the current env.template but missing from admin/.env — add it (commented if not in use)"
    done

If this reports a FAIL on an already-configured instance, add the missing
key to `.env` (commented out if the corresponding feature isn't in use, set
if it is) rather than re-copying the whole file — `.env` holds real operator
secrets and must never be wholesale-overwritten from the template. See
`/opt/aaas/platform/sop/upgrade-platform.md` step 9.4, which runs this same
check automatically on every platform upgrade.

If Telegram was enabled in Step 3.1, also verify:

    grep -q "^TELEGRAM_BOT_TOKEN=." /opt/aaas/platform/admin/.env     && echo "OK: telegram token set"
    grep -q "^TELEGRAM_ALLOWED_USERS=." /opt/aaas/platform/admin/.env && echo "OK: telegram allow list set"
    grep -q "^TELEGRAM_HOME_CHANNEL=." /opt/aaas/platform/admin/.env \
      && echo "OK: home channel set" \
      || echo "FAIL: TELEGRAM_HOME_CHANNEL was not set in .env — Ask The Operator step was skipped or incomplete"
    grep -q "^TELEGRAM_ALLOWED_USERS=$" /opt/aaas/platform/admin/.env \
      && echo "FAIL: TELEGRAM_ALLOWED_USERS is empty — allow list is mandatory when Telegram is enabled" \
      || echo "OK: allow list non-empty"

Do not check `home_chat_id` in config.yaml as evidence of anything — it is
dead config the gateway never reads (see Step 3.1, item 1). Checking it
would validate the wrong file and could pass even when Telegram is
completely unconfigured.

If Telegram was declined, confirm the lines remain commented out instead:

    grep -q "^# TELEGRAM_BOT_TOKEN=" /opt/aaas/platform/admin/.env && echo "OK: telegram left disabled"

After Step 7 starts Hermes, this validation step only confirms config was
*written* correctly — it does not confirm the gateway actually connected.
Run Step 3.1 item 6's log check after Step 7 for that.

## Step 7 — Start Hermes and Verify Proxy

    sudo -u aaas -H bash -c 'cd /opt/aaas/platform/admin && set -a && . ./.env && set +a && hermes dashboard --no-open'

In a second terminal, confirm the proxy intercepts LLM calls:

    sudo -u aaas -H bash -c 'cd /opt/aaas/platform/admin && set -a && . ./.env && set +a && hermes -z "Reply with the single word: PROXY_OK"'

Expected: a response containing PROXY_OK. If the call fails with a proxy or
SSL error, re-check Step 4 (CA trust) and Step 5 (proxy vars in .env).

## Step 8 — Install Watchdog

Admin Hermes is covered by the platform-wide watchdog, not a dedicated
script — it also covers Agent Vault and every tenant container, with Agent
Vault checked first as the priority-0 dependency. If it's already installed
(e.g. from setting up Agent Vault or onboarding a tenant), skip this step.

    sudo /opt/aaas/platform/scripts/aaas-watchdog.sh --install

Verify:
    systemctl status aaas-watchdog.timer
    # Expected: active (waiting)

See /opt/aaas/platform/incidents/hermes-admin-failure.md for the recovery
playbook OpenCode uses when the watchdog detects Hermes admin is down.

## Reporting

Write a task report using /opt/aaas/platform/sop/write-report.md.

Include: provider name, model name, dashboard host/port, files created, vault
name, agent token name (hermes_admin), CA trust status, proxy verification
result, watchdog install status, Telegram enabled/declined status, and (if
enabled) allow-list size and test message delivery result per user ID.

Never include: API keys, vault tokens, passwords, auth secrets, Telegram bot
tokens, or any credential-shaped value.
