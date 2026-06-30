---
name: manage-agent-vault
description: >
  Runtime skill for the Hermes admin agent to inspect and manage Agent Vault.
  Agent Vault is used exclusively for LLM API keys — its MITM proxy pattern
  only applies to HTTP/HTTPS calls to LLM providers. Non-LLM credentials
  (SMTP, webhooks, Telegram tokens, etc.) go in .env directly, not in Agent
  Vault. Use this skill for day-to-day LLM key operations: listing vaults and
  credentials, rotating LLM provider keys, minting or revoking agent tokens,
  and verifying proxy health. For initial one-time vault setup, follow
  /opt/aaas/platform/sop/setup-agent-vault.md. For full tenant provisioning,
  follow /opt/aaas/platform/sop/provision-tenant-vault.md.
---

# Skill: Manage Agent Vault

> **Scope:** Agent Vault manages LLM API keys only. Its value is the MITM
> proxy pattern — the real key never enters the agent's context; it is injected
> at the network layer for HTTP/HTTPS calls to LLM providers. Non-LLM
> credentials (SMTP passwords, Telegram tokens, webhook secrets, etc.) do not
> go through Agent Vault. They belong in `.env` and are written there directly
> by the admin agent (for the admin agent's own integrations) or by the tenant
> agent after owner confirmation (for tenant integrations).

**Prerequisite:** Agent Vault is running and healthy before any operation here.

    /opt/aaas/platform/scripts/agent-vault-health.sh
    # Expected: all PASS

If any check fails, stop and follow /opt/aaas/platform/sop/setup-agent-vault.md
or /opt/aaas/platform/incidents/agent-vault-failure.md before continuing.

## Preconditions

- `agent-vault` CLI is authenticated: `agent-vault vault list` must succeed
- Never print, log, store, or reveal the value of any credential or token
- Always confirm with the operator before modifying a production vault
- Vault operations that remove credentials or tokens are irreversible

---

## 1 — Inspect: List Vaults and Their Contents

    # List all vaults
    agent-vault vault list

    # List credentials stored in a vault
    agent-vault vault credential list --vault {vault-name}

    # List registered services (proxied hosts)
    agent-vault vault service list --vault {vault-name}

    # List agent tokens scoped to a vault
    agent-vault agent list --vault {vault-name}

Use `admin-vault` for the Hermes admin agent's own vault and
`{tenant-id}-vault` for tenant vaults.

---

## 2 — Add or Rotate a Credential

Use this when onboarding a new provider for an existing vault, or when a
credential must be rotated (key compromised or expired).

### 2.1 Provider hostname reference

| Provider     | Hostname              | Env var               |
|--------------|-----------------------|-----------------------|
| OpenRouter   | openrouter.ai         | OPENROUTER_API_KEY    |
| OpenAI       | api.openai.com        | OPENAI_API_KEY        |
| Anthropic    | api.anthropic.com     | ANTHROPIC_API_KEY     |
| Nous         | api.nous.ai           | NOUS_API_KEY          |
| OpenCode Zen | opencode.ai           | OPENCODE_API_KEY      |

### 2.2 Store or update the credential

    agent-vault vault credential set {PROVIDER_VAR}={real-api-key} --vault {vault-name}

`credential set` is idempotent — it creates the credential if absent or
overwrites the existing value if present.

### 2.3 Register or re-register the service

    agent-vault vault service add \
      --vault {vault-name} \
      --name {PROVIDER_VAR} \
      --host {hostname} \
      --auth-type Bearer \
      --token-key {PROVIDER_VAR}

If the service is already registered (key rotation only), skip this step.
Confirm registration:

    agent-vault vault service list --vault {vault-name}

### 2.4 Update the placeholder in `.env`

After credential set, ensure the env file still holds the placeholder — never
the real key:

    # For tenant vaults:
    PROVIDER_VAR={PROVIDER_VAR}
    grep -qx "${PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/tenants/{tenant-id}/.env \
      && echo "OK: placeholder intact" \
      || echo "WARN: check .env — placeholder may be missing"

    # For the admin vault:
    grep -qx "${PROVIDER_VAR}=routed-via-agent-vault" /opt/aaas/platform/admin/.env \
      && echo "OK: placeholder intact" \
      || echo "WARN: check admin .env"

If the placeholder is missing (e.g. a real key is present), replace it:

    sed -i "s|^${PROVIDER_VAR}=.*|${PROVIDER_VAR}=routed-via-agent-vault|" {env-file-path}

Then verify no live key pattern remains:

    grep -E "(sk-[A-Za-z0-9_-]{10,}|sk-ant-|sk-or-v1-)" {env-file-path}
    # Expected: no output

### 2.5 Force-recreate the container (tenant only)

The proxy token is baked into the running environment at container start.
After a credential change, restart the tenant container so the new credential
is picked up:

    docker compose -f /opt/aaas/tenants/{tenant-id}/docker-compose.yaml \
      up -d --force-recreate hermes_{tenant-id}

For the admin agent's own credential, restart hermes after sourcing `.env`:

    # Restart is handled by the watchdog or manually:
    systemctl --user restart hermes-admin-watchdog.timer

---

## 3 — Mint an Agent Token

Use when a new agent identity is needed for an existing vault (e.g. adding a
second agent instance, or replacing a revoked token).

    NEW_TOKEN=$(agent-vault agent create \
      --vault {vault-name}:proxy \
      --name {agent-name} \
      --token-only)

Inject the token into the relevant `.env`:

    # Tenant
    sed -i "s|^AGENT_VAULT_TOKEN=.*|AGENT_VAULT_TOKEN=${NEW_TOKEN}|" \
      /opt/aaas/tenants/{tenant-id}/.env

    # Admin
    sed -i "s|^AGENT_VAULT_TOKEN=.*|AGENT_VAULT_TOKEN=${NEW_TOKEN}|" \
      /opt/aaas/platform/admin/.env

Also update the proxy URLs to use the new token:

    sed -i "s|^HTTP_PROXY=.*|HTTP_PROXY=http://${NEW_TOKEN}@{proxy-host}:14322|" {env-file-path}
    sed -i "s|^HTTPS_PROXY=.*|HTTPS_PROXY=http://${NEW_TOKEN}@{proxy-host}:14322|" {env-file-path}

Proxy host is `localhost:14322` for the admin agent (runs on host) and
`agent-vault-proxy-{tenant-id}:14322` for tenant containers (the per-tenant
forwarding sidecar — never `agent-vault:14322` directly, see
provision-tenant-vault.md step 1b).

Force-recreate the container after `.env` changes (see step 2.5).

---

## 4 — Revoke an Agent Token

Use when an agent instance is decommissioned or a token is compromised.

    agent-vault agent delete {agent-name} --vault {vault-name}

Confirm deletion:

    agent-vault agent list --vault {vault-name}
    # Expected: {agent-name} is absent

Update `.env` to remove the revoked token, then force-recreate so the agent
is no longer started with a dead token.

---

## 5 — Configure Tenant LLM Key via Bidirectional Channel

This section describes the admin agent's behaviour when handling an
`llm_key_change` request arriving via the bidirectional channel between the
Hermes admin agent and tenant agents (tenant-side: `tenant-contact-admin.md`;
admin-side: `handle-tenant-request.md`). The channel is operational — this is
the same flow `handle-tenant-request.md`'s `llm_key_change` section delegates
to in step 3.

Agent Vault is involved here specifically because LLM API keys are the one
credential type that must never enter the agent's context. All other tenant
credential changes (SMTP passwords, webhook secrets, Telegram tokens, etc.)
are handled by the tenant agent directly via `.env` append after owner
confirmation — those never come to the admin agent.

The tenant's request blocks on an immediate reply, so the operator's
confirmation virtually never arrives in time to act within that same turn —
`handle-tenant-request.md` replies to the tenant with a pending status and
notifies the operator without waiting, then completes the steps below on a
later turn once the operator has actually responded (either when checking
back proactively, or when the tenant sends a follow-up asking for status).
Never run these steps gated on an in-progress wait for the operator's reply.

When the operator has confirmed an LLM provider key change for a tenant:

1. Verify the request originates from the expected tenant agent identity.
2. Obtain the new key value from the operator — the key must never come from
   the tenant agent itself.
3. Confirm the key change with the operator before writing anything.
4. Run steps 2.2–2.4 above against `{tenant-id}-vault` to store the new key
   and verify the placeholder in `.env` remains `routed-via-agent-vault`.
5. Force-recreate the tenant container (step 2.5) so the new key takes effect.
6. Confirm success back to the tenant channel without revealing the key value.
7. Write a task report (never include the key value).

---

## 6 — Verify Proxy Health After Changes

After any LLM key, token, or service change, confirm the proxy is
intercepting calls correctly:

    # For tenant containers:
    docker exec hermes_{tenant-id} sh -c \
      'set -a; . /opt/data/.env; set +a; \
       hermes -z "Reply with the single word: PROXY_OK"'

    # For the admin agent (run from /opt/aaas/platform/admin):
    cd /opt/aaas/platform/admin
    set -a; . ./.env; set +a
    hermes -z "Reply with the single word: PROXY_OK"

Expected: a response containing `PROXY_OK`. A proxy or SSL error means the
token, placeholder, or CA trust is misconfigured — re-check steps 2–4 above.

---

## Reporting

Write a task report using /opt/aaas/platform/sop/write-report.md.

Include: vault name, operation performed, service name, agent token name,
proxy verification result, container restart status.

Never include: LLM API keys, vault tokens, or any credential-shaped value.

