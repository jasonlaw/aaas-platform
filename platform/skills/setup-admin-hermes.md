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
- curl and git are available (the official Hermes installer needs them; on
  Linux also make sure xz-utils is installed — the installer downloads
  Node.js as a .tar.xz archive)
- Never print, log, or store API keys or passwords in task reports
- This skill installs Hermes via the official per-user installer, as the
  same operator account that owns the rest of /opt/aaas (the one that ran
  platform setup) — no sudo for the install itself, and no dedicated
  service account. There is exactly one identity for the whole platform.
  The only steps in this skill that do need sudo are installing the Agent
  Vault CA into the host trust store (Step 4) and, later, installing the
  watchdog systemd unit (Step 8) — both unrelated to Hermes's own install.

## Ask The Operator

Collect before writing any files. Never write the real API key anywhere
except Agent Vault (Step 5).

1. LLM provider and model. Recommended: openrouter / openai/gpt-4.1-mini
1.1. Fallback LLM provider and model (optional). Ask whether the operator
   wants automatic failover to a backup provider:model if the primary
   provider fails (rate limits, server errors, auth failures) — see
   https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers.
   If yes, also collect the fallback's real LLM API key — stored in Agent
   Vault only, same as the primary key, never in .env. If declined, proceed
   with no fallback configured — this is the common case and is not an error.
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

Install Hermes using the official installer, in its default per-user mode
— no `sudo`, and it runs as whichever account is doing this setup (the
same operator that already owns the rest of /opt/aaas). This replaces an
earlier design that hand-built a venv with `pip install 'hermes-agent[...]'`
under a dedicated `aaas` service account; that approach is retired because
(a) it duplicated permission bookkeeping that /opt/aaas already handles by
being owned by the operator throughout, and (b) PyPI has historically
lagged the `hermes-agent` git source (e.g. serving 0.13.0 while source was
already at 0.14.0), which was the root cause of a previously-unconfirmed
Telegram/`dashboard_auth` packaging gap. The official installer clones and
builds from git directly, sidestepping that lag entirely:

    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser

`--skip-browser` skips the Playwright/Chromium install — this is a headless
server and admin Hermes doesn't need in-agent browser automation. Omit it
if that's ever needed later; it can be added afterward with
`hermes tools`.

This installs code + venv under `~/.hermes/hermes-agent/` and writes the
launcher to `~/.local/bin/hermes`. Confirm it resolved onto PATH (most
distros already add `~/.local/bin` to a login shell's PATH by default):

    hermes --version

If that fails, add it explicitly — this is the one-line fallback the
official docs themselves recommend for exactly this case:

    grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    hermes --version

Also export `HERMES_HOME` in the shell profile now, not just inline for the
one-off Mnemosyne commands below. Without a persistent export, running
`hermes` interactively from a normal login shell falls back to
`~/.hermes/config.yaml` — the installer's own default profile, with its own
default model — instead of this platform's `/opt/aaas/platform/admin`
profile and the provider/model configured in Step 2's `config.yaml`. This
fails silently: no error, just the wrong model. (The systemd service in
Step 7 doesn't need this — it gets `HERMES_HOME` from `.env` via
`EnvironmentFile=`; this is specifically for interactive CLI use. Step 3.1
item 4 covers the same fallback in the gateway-process context.)

    grep -qxF 'export HERMES_HOME=/opt/aaas/platform/admin' ~/.bashrc || \
      echo 'export HERMES_HOME=/opt/aaas/platform/admin' >> ~/.bashrc
    source ~/.bashrc

Then add the two extra packages this platform needs on top of the base
install — the Mnemosyne memory integration — into the same managed venv
the installer just created. The installer already provisioned `uv`; use it
with `--python` pointed at the managed venv rather than guessing its exact
folder name (installer versions have used both `venv/` and `.venv/`):

    HERMES_VENV_PY="$(find ~/.hermes/hermes-agent -maxdepth 2 -type f -path '*/bin/python*' ! -path '*-config*' | head -1)"
    test -n "$HERMES_VENV_PY" || { echo "FAIL: could not locate the Hermes venv python under ~/.hermes/hermes-agent"; exit 1; }
    uv pip install --python "$HERMES_VENV_PY" --upgrade \
      'mnemosyne-memory[embeddings]' mnemosyne-hermes

Then activate the Mnemosyne plugin into the admin Hermes profile. This is
a separate step from the pip install — the pip package only places the
plugin code on disk; the `install` subcommand creates the symlink under
`~/.hermes/plugins/mnemosyne` that Hermes's plugin loader requires.
`HERMES_HOME` must be exported so both commands target the admin profile,
not the default `~/.hermes` location. `memory_enabled: false` in
`config.yaml` disables native Hermes memory (intentional — Mnemosyne
replaces it); it does not affect this plugin activation path:

    HERMES_HOME=/opt/aaas/platform/admin mnemosyne-hermes install
    HERMES_HOME=/opt/aaas/platform/admin hermes memory setup

## Step 2 — Create Admin Profile

    mkdir -p /opt/aaas/platform/admin

Copy only missing files (never overwrite without operator confirmation):
- admin-hermes/SOUL.md.template  -> admin/SOUL.md
- admin-hermes/MEMORY.md.template -> admin/memories/MEMORY.md
- admin-hermes/USER.md.template  -> admin/memories/USER.md
- admin-hermes/config.yaml.template -> admin/config.yaml
- admin-hermes/env.template -> admin/.env

    mkdir -p /opt/aaas/platform/admin/memories
    mkdir -p /opt/aaas/platform/admin/mnemosyne/data
    chmod 700 /opt/aaas/platform/admin
    chmod 600 /opt/aaas/platform/admin/.env

No `chown` needed — this directory is already owned by the operator
running this setup, same as the rest of `/opt/aaas`. The `chmod` calls
above still matter: they keep `.env` and mnemosyne data unreadable by
other local accounts on a shared box, same intent as before, just without
a dedicated identity to own it.

**Seed Mnemosyne with `admin/memories/MEMORY.md` and `admin/memories/USER.md`.** These are
intentionally one-time seeds (see CHANGELOG.md's Step 2 file audit) — do
this now, once, right after they're copied above; nothing else in this repo
re-seeds them later. Uses the same SDK-based script tenant onboarding uses,
run with the admin venv's own python and `MNEMOSYNE_DATA_DIR` pointed at the
path just set in `.env`:

    HERMES_VENV_PY="$(find ~/.hermes/hermes-agent -maxdepth 2 -type f -path '*/bin/python*' ! -path '*-config*' | head -1)"
    test -n "$HERMES_VENV_PY" || { echo "FAIL: could not locate the Hermes venv python under ~/.hermes/hermes-agent"; exit 1; }
    MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data \
      "$HERMES_VENV_PY" /opt/aaas/platform/tenant-hermes/scripts/seed-mnemosyne.py /opt/aaas/platform/admin/memories/MEMORY.md fact
    MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data \
      "$HERMES_VENV_PY" /opt/aaas/platform/tenant-hermes/scripts/seed-mnemosyne.py /opt/aaas/platform/admin/memories/USER.md preference

Each call exits non-zero if any individual fact fails to store — treat a
non-zero exit as a failed seed, not a partial success.

## Step 3 — Configure Files

Update /opt/aaas/platform/admin/config.yaml with provider, model, dashboard
values. If a fallback provider was collected in Ask The Operator, also add a
top-level `fallback_providers:` list with one entry (`provider` and `model`,
matching admin-hermes/config.yaml.template's commented example) — never write
the fallback API key into config.yaml, it is scrubbed the same way as the
primary key in Step 5.7. If no fallback provider was collected, leave the
`fallback_providers` block commented out exactly as shipped. Leave .env
untouched until Step 5 — real API key must never be written into .env.

**`model.provider` must be set to exactly one Provider ID listed in
`/opt/aaas/platform/reference/llm-provider-catalog.md`** (Step 5.2 reproduces
the current table) **and nothing else.** There is no supported
custom-provider mechanism anywhere in this platform — no top-level
`providers:` list, no `api_key_env_var` or `key_env` field, no `base_url`,
no per-provider override block. If a 401/model-routing error occurs against
a catalog provider, the fix is a config or model-name correction within the
existing single `model:` block, never the introduction of a new provider
block or a new env var name not already present (commented or not) in
`admin-hermes/env.template`. If a `providers:` block, `base_url` key, or any
non-catalog env var is already present from a prior session, that is prior
drift to be removed, not a pattern to extend — flag it under Issues and
revert to the single supported `model:` field and the exact env var name
from the catalog. If source code or external docs suggest a different env
var name than what the catalog lists, escalate to the operator — do not
write any credential under an undocumented name.

**Never ask the operator for the API key env var name.** Given only
`provider/model` (e.g. `opencode-zen/big-pickle`) or separate `provider =`
and `model =` answers, look up the Provider ID in the catalog and derive the
env var mechanically — the catalog's derivation rule is deterministic. The
operator only needs to be asked for: (1) the provider/model itself, if not
given, and (2) the real API key value. If the named provider is not in the
catalog, or falls under the catalog's Exceptions section (OAuth-only or
multi-credential providers), stop and follow the catalog's escalation
guidance instead of guessing.

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
   enabled — no error, and (admin Hermes does not keep a process log, see
   Step 7) nothing written anywhere to reveal it either. Step 7 below always
   sets `HERMES_HOME` via the systemd unit's `EnvironmentFile`, so this only
   bites a manual/nohup start done outside this skill; if Hermes is ever
   started by hand, `HERMES_HOME` must be exported first.

5. After Step 7 starts Hermes, send a test message to the configured
   TELEGRAM_HOME_CHANNEL value to verify delivery:

       curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d chat_id="${TELEGRAM_HOME_CHANNEL}" \
         --data-urlencode text="Admin Hermes Telegram channel is live."

   A `400 Bad Request: chat not found` or `403 Forbidden` means that user
   has not yet opened the bot and sent /start — this is expected for users
   who haven't initiated contact yet, not a setup failure. Note it in the
   task report rather than treating it as blocking.

6. Treat the test message in item 5 as the definitive signal that Telegram
   connected, not just that the process started. Admin Hermes does not keep
   a process log (see Step 7), so there is no gateway log to grep for a
   "Connected to Telegram" line. Delivery, or the expected `400`/`403` for a
   user who hasn't opened the bot yet, both confirm the gateway is up and
   read its Telegram config. If that request instead times out, or the
   dashboard itself is unreachable (`curl -sf http://127.0.0.1:9119/`),
   `HERMES_HOME` likely was not exported when the process started — restart
   per Step 7, which always sets it via the systemd unit's
   `EnvironmentFile`, and re-send the item 5 test message.

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

Full catalog: `/opt/aaas/platform/reference/llm-provider-catalog.md` — read
it for the current list, the derivation rule, and the exceptions that must
be escalated rather than auto-configured. Most commonly used at the time of
writing:

| Provider ID    | Hostname              | Env var               |
|----------------|------------------------|------------------------|
| `openrouter`   | openrouter.ai          | OPENROUTER_API_KEY    |
| `openai`       | api.openai.com         | OPENAI_API_KEY        |
| `anthropic`    | api.anthropic.com      | ANTHROPIC_API_KEY     |
| `nous`         | api.nous.ai            | NOUS_API_KEY          |
| `opencode-zen` | opencode.ai            | OPENCODE_ZEN_API_KEY  |
| `opencode-go`  | opencode.ai            | OPENCODE_GO_API_KEY   |

The **Env var** column is exact and non-negotiable — it is the only name
`{PROVIDER_VAR}` may take throughout Step 5, and it is the only name that
may appear (commented or not) in `admin/.env`. Do not rename, abbreviate,
or invent a variant even if it seems more descriptive — Agent Vault's
service registration in 5.3 and the proxy injection in 5.5 are keyed to
this exact string. This excerpt is a convenience only — the catalog file
above is authoritative and is where new providers get added. If runtime
source code or provider docs appear to contradict either this excerpt or
the full catalog, **stop and escalate to the operator** before writing any
credential — do not self-resolve the conflict.

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

The Agent Vault MITM proxy is scoped to LLM API calls only — it is not
equipped to handle Telegram's Bot API or HuggingFace model downloads. Any
host not in NO_PROXY gets routed through the proxy anyway and fails with a
502 (Telegram connect, Mnemosyne embedding model download, etc.), so the
default NO_PROXY here includes those hosts up front rather than leaving it
for the operator to discover after Step 3.1 fails.

    PROVIDER_VAR={PROVIDER_VAR}
    sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" \
      /opt/aaas/platform/admin/.env

    cat >> /opt/aaas/platform/admin/.env <<PROXYEOF

    # Agent Vault proxy — injected by setup-admin-hermes
    # Admin Hermes runs on the host; proxy is localhost:14322.
    HTTP_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322
    HTTPS_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322
    NO_PROXY=localhost,127.0.0.1,api.telegram.org,telegram.org,*.telegram.org,huggingface.co
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

### 5.7 (Optional) Provision the fallback provider credential

Skip entirely if no fallback provider was collected in Ask The Operator.
Otherwise, same pattern as 5.1–5.6, under the fallback's own provider
variable and hostname (see the table in 5.2) — both credentials live in the
same `admin-vault`:

    agent-vault vault credential set {FALLBACK_PROVIDER_VAR}={fallback-real-api-key} --vault admin-vault

    agent-vault vault service add \
      --vault admin-vault \
      --name {FALLBACK_PROVIDER_VAR} \
      --host {fallback-hostname} \
      --auth-type Bearer \
      --token-key {FALLBACK_PROVIDER_VAR}

    FALLBACK_PROVIDER_VAR={FALLBACK_PROVIDER_VAR}
    sed -i "s|^${FALLBACK_PROVIDER_VAR}=.*|${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault|" \
      /opt/aaas/platform/admin/.env

Verify the same two checks as 5.6, against `${FALLBACK_PROVIDER_VAR}` this
time:

    grep -qx "${FALLBACK_PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/platform/admin/.env \
      && echo "OK: fallback placeholder set" \
      || echo "FAIL: fallback real key not scrubbed"
    grep -E "(sk-[A-Za-z0-9_-]{10,}|sk-ant-|sk-or-v1-)" /opt/aaas/platform/admin/.env
    # Expected: no output.

## Step 6 — Validate Installation

    command -v hermes && hermes --version
    test -f /opt/aaas/platform/admin/SOUL.md     && echo "OK: SOUL.md"
    test -f /opt/aaas/platform/admin/memories/USER.md     && echo "OK: USER.md"
    test -f /opt/aaas/platform/admin/memories/MEMORY.md   && echo "OK: MEMORY.md"
    HERMES_VENV_PY="$(find ~/.hermes/hermes-agent -maxdepth 2 -type f -path '*/bin/python*' ! -path '*-config*' | head -1)"
    MNEMOSYNE_DATA_DIR=/opt/aaas/platform/admin/mnemosyne/data \
      "$HERMES_VENV_PY" -c "from mnemosyne import get_stats; s=get_stats(); assert s.get('working',0)+s.get('episodic',0) > 0, s; print('OK: mnemosyne has seeded facts')"
    test -f /opt/aaas/platform/admin/config.yaml && echo "OK: config.yaml"
    test -f /opt/aaas/platform/admin/.env        && echo "OK: .env"
    grep -q "provider: mnemosyne"       /opt/aaas/platform/admin/config.yaml && echo "OK: mnemosyne"
    grep -q "memory_enabled: false"     /opt/aaas/platform/admin/config.yaml && echo "OK: memory disabled"
    test -L ~/.hermes/plugins/mnemosyne \
      && echo "OK: mnemosyne plugin symlink present" \
      || echo "FAIL: mnemosyne plugin symlink missing — re-run: HERMES_HOME=/opt/aaas/platform/admin mnemosyne-hermes install && HERMES_HOME=/opt/aaas/platform/admin hermes memory setup"
    grep -q "user_profile_enabled: false" /opt/aaas/platform/admin/config.yaml && echo "OK: user profile disabled"
    grep -q "routed-via-agent-vault" /opt/aaas/platform/admin/.env        && echo "OK: placeholder"
    grep -q "HTTP_PROXY"             /opt/aaas/platform/admin/.env        && echo "OK: proxy config"
    grep -q "SSL_CERT_FILE"          /opt/aaas/platform/admin/.env        && echo "OK: SSL_CERT_FILE"
    agent-vault vault credential list --vault admin-vault
    agent-vault vault service list --vault admin-vault
    agent-vault agent list --vault admin-vault

**Reject any invented provider config.** These two checks must both pass —
if either fails, this is drift from an earlier session (possibly one that
predates this checklist), not a valid configuration; remove the offending
block/line and re-derive from the catalog
(`/opt/aaas/platform/reference/llm-provider-catalog.md`) before continuing:

    grep -q "^providers:" /opt/aaas/platform/admin/config.yaml \
      && echo "FAIL: unsupported top-level providers: block present — remove, use model.provider only" \
      || echo "OK: no custom providers block"
    ALLOWED_VARS=$(grep -oE '\`[A-Z_]+_API_KEY\`' \
      /opt/aaas/platform/reference/llm-provider-catalog.md \
      | tr -d '`' | sort -u | paste -sd'|' -)
    grep -E "^[A-Z_]+_API_KEY=" /opt/aaas/platform/admin/.env \
      | grep -vE "^(${ALLOWED_VARS})=" \
      && echo "FAIL: unrecognized *_API_KEY variable — must be a name from the catalog, exactly" \
      || echo "OK: only catalog-listed provider env var names present"

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
Run Step 3.1 item 6's test-message check after Step 7 for that.

## Step 7 — Install Gateway Service and Verify Proxy

Admin Hermes (the gateway/dashboard process) runs as a systemd `--user`
service, not a bare backgrounded process — this gives it the same
crash/reboot auto-restart guarantee Docker's `restart: unless-stopped`
already gives every other component. A previous version of this skill
started it with a plain `nohup ... &`, which had no recovery mechanism at
all beyond the watchdog's 5-minute poll (Step 8) and did not survive a
reboot.

    mkdir -p ~/.config/systemd/user
    cp /opt/aaas/platform/admin-hermes/aaas-admin-hermes.service \
       ~/.config/systemd/user/aaas-admin-hermes.service
    systemctl --user daemon-reload
    systemctl --user enable --now aaas-admin-hermes.service

`loginctl enable-linger` is required once so this unit keeps running after
the operator logs out and starts again on boot with no active login
session — the normal case on a headless server. Needs sudo the one time:

    sudo loginctl enable-linger "$USER"

Verify the service is up:

    systemctl --user status aaas-admin-hermes.service
    # Expected: active (running)

The dashboard's first start after a fresh install (or after an upgrade
that touches its bundled web UI) does a TypeScript/Vite build before it
starts serving — this can take up to ~60 seconds and is expected, not a
failure. Wait for it rather than restarting the service if the health
check below doesn't respond immediately:

    for i in $(seq 1 40); do
      curl -sf http://127.0.0.1:9119/ >/dev/null 2>&1 && echo "OK: dashboard up" && break
      sleep 2
    done

In a second terminal, confirm the proxy intercepts LLM calls:

    cd /opt/aaas/platform/admin && set -a && . ./.env && set +a && hermes -z "Reply with the single word: PROXY_OK"

No `sudo -u` wrapper needed — Hermes runs as whichever account this setup
is running as, the same one that owns `/opt/aaas/platform/admin`.

Expected: a response containing PROXY_OK. If the call fails with a proxy or
SSL error, re-check Step 4 (CA trust) and Step 5 (proxy vars in .env).

If `hermes -z` hangs instead of erroring — it has no built-in timeout and
gives no diagnostic output while stuck — don't wait it out. Interrupt it
and run a bounded check against the proxy directly first, which fails fast
with an actual error instead of a silent hang. Use the hostname for
whichever provider was configured in Step 5.2 (e.g. `openrouter.ai` for
OpenRouter, `api.anthropic.com` for Anthropic):

    curl -sS --max-time 10 -v --proxy "http://${AGENT_VAULT_TOKEN}@localhost:14322" \
      "https://{provider-hostname}/"
    # A connection refused / timeout here points at the proxy or container
    # network (see docs/troubleshooting.md's WSL2 nftables entry if this
    # host is Docker Desktop on WSL2). A clean HTTP response (even an auth
    # error from the provider itself) means the proxy path is fine and the
    # original hang was Hermes-side — retry `hermes -z`.

## Step 8 — Confirm Watchdog Active

Admin Hermes is covered by the platform-wide watchdog, which was installed
during `setup-agent-vault.md` step 6 (the canonical installation point).
Confirm it is active before proceeding:

    systemctl status aaas-watchdog.timer
    # Expected: active (waiting)

If the timer is not active (e.g. this host skipped `setup-agent-vault.md`),
install it now:

    sudo /opt/aaas/platform/scripts/aaas-watchdog.sh --install
    systemctl status aaas-watchdog.timer
    # Expected: active (waiting)

The watchdog is a second, independent layer on top of the systemd `--user`
service installed in Step 7. systemd already restarts admin Hermes if the
process itself dies (`Restart=on-failure`) or on reboot — the watchdog
instead polls whether the dashboard is actually *responding* every 5 minutes
and escalates to OpenCode with the recovery playbook when it isn't (e.g. the
process is alive but the Agent Vault proxy is failing, which systemd alone
would never detect). When the watchdog does need to restart admin Hermes,
it does so via `systemctl --user restart aaas-admin-hermes.service` rather
than a raw `nohup`, so both layers manage the same single process.

See /opt/aaas/platform/incidents/hermes-admin-failure.md for the recovery
playbook OpenCode uses when the watchdog detects Hermes admin is down.

## Reporting

Write a task report using /opt/aaas/platform/sop/write-report.md.

Include: provider name, model name, dashboard host/port, files created, vault
name, agent token name (hermes_admin), CA trust status, proxy verification
result, watchdog install status, Telegram enabled/declined status, and (if
enabled) allow-list size and test message delivery result per user ID.
Fallback provider/model configured (or declined), and if configured, the
fallback credential's vault/service registration status.

Never include: API keys, vault tokens, passwords, auth secrets, Telegram bot
tokens, or any credential-shaped value.