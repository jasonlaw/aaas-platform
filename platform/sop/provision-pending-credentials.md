# SOP: Provision Pending Credentials

## Purpose
Process `PENDING_VAULT_` entries written by a tenant agent into the tenant's
`.env`, register each credential in Agent Vault, replace the entry with
`{NAME}=routed-via-agent-vault`, and force-recreate the container.

This SOP is called by the admin agent whenever `check-tenant.sh` reports
`pending_vault_credentials_require_admin_action` — during a routine health
check (`monitor-health.md` step 6.1) or at any other time the WARN is seen.
Run it immediately; do not defer to the next health check cycle, since the
plaintext credential sits in `.env` until this SOP runs.

This SOP handles credentials for external services the tenant agent connects
to on the owner's behalf (database, email, payment APIs, etc.). It does not
cover LLM provider keys — those are handled exclusively by
`provision-tenant-vault.md` during onboarding and are never written as
`PENDING_VAULT_` entries.

## Pre-requisites
- Agent Vault container is running and healthy:
  `/opt/aaas/platform/scripts/agent-vault-health.sh`
- `agent-vault` CLI is installed and authenticated on the host:
  `agent-vault vault list` must succeed without error
- The tenant's vault already exists (created during onboarding by
  `provision-tenant-vault.md` step 1)

## Steps

### 1. Read the pending entries
```bash
grep '^PENDING_VAULT_' /opt/aaas/tenants/{tenant-id}/.env
```
Each line has the format:
```
PENDING_VAULT_{NAME}={value}|host={hostname}|auth={auth-type}
```
Parse each one: extract `NAME`, `value`, `hostname`, and `auth-type`.

If the parsed hostname or auth-type is missing or malformed, do not guess —
ask the operator to clarify, then have the tenant agent rewrite the
`PENDING_VAULT_` entry with the corrected values before continuing.

Verify `auth-type` is a valid `agent-vault vault service add --auth-type`
value before proceeding to step 3a:
```bash
agent-vault vault service add --help
```
Common values include `Bearer` (bearer token), `Basic` (basic auth
username/password), and `header` (generic value injected as a named header) —
confirm the exact supported set against `--help` output for the CLI version
installed, since this can vary by release.

### 2. Determine new vs. update
For each entry, check whether a service for this `NAME` already exists in
Agent Vault:
```bash
agent-vault vault service list --vault {tenant-id}-vault
```
- Not listed → new registration path (step 3a).
- Already listed → update path (step 3b).

### 3a. New credential (service not listed)
```bash
agent-vault vault credential set {NAME}={value} --vault {tenant-id}-vault
agent-vault vault service add \
  --vault {tenant-id}-vault \
  --name {NAME} \
  --host {hostname} \
  --auth-type {auth-type} \
  --token-key {NAME}
```

Then update `NO_PROXY` in the tenant `.env`: remove `{hostname}` from
`NO_PROXY` if it was there (it should now route through the proxy, not bypass
it). If it was not in `NO_PROXY`, no change needed — unregistered hosts are
already denied by default.

### 3b. Update (service already listed)
```bash
agent-vault vault credential set {NAME}={value} --vault {tenant-id}-vault
```
No `service add` needed — the service mapping (hostname, auth-type) stays the
same. Only the credential value changes. Running `service add` on an existing
service name may error or create duplicates depending on Agent Vault CLI
version, so only run it in the new-registration path (3a).

### 4. Replace the pending entry with the placeholder
```bash
sed -i "s|^PENDING_VAULT_{NAME}=.*|{NAME}=routed-via-agent-vault|" \
  /opt/aaas/tenants/{tenant-id}/.env
```

### 5. Verify no pending entries remain
```bash
grep '^PENDING_VAULT_' /opt/aaas/tenants/{tenant-id}/.env
# Expected: no output
```

### 6. Force-recreate the tenant container
```bash
docker compose up --force-recreate --no-deps -d hermes_{tenant-id}
```
Never use `docker compose restart` here — it does not guarantee the updated
`.env` is reloaded.

### 7. Confirm with the harness
```bash
/opt/aaas/platform/harness/check-tenant.sh {tenant-id}
```
Confirm `pending_vault_credentials_require_admin_action` is gone and
`no_pending_vault_credentials` shows PASS.

### 8. Write a task report
Follow `/opt/aaas/platform/sop/write-report.md`. Include each credential
`NAME` and `hostname` processed, and whether each was a new registration or an
update. Never include credential values in the report.

## Notes
- Never log or report the actual credential value — only `NAME` and `hostname`
  are safe to record, in this SOP's report and everywhere else.
- The plaintext credential exists in `.env` only between the tenant agent
  writing it and this SOP running. Run this SOP promptly when the WARN
  appears — do not batch it with unrelated work.
- The `auth-type` field in the `PENDING_VAULT_` line is set by the tenant
  agent based on what the owner described, not validated by the tenant agent
  against the Agent Vault CLI. Always verify it against
  `agent-vault vault service add --help` before running step 3a.
- If the parsed hostname or auth-type is missing or malformed, do not guess —
  ask the operator to clarify, then have the tenant agent rewrite the
  `PENDING_VAULT_` entry with the corrected values.
- This SOP must not touch `provision-tenant-vault.md`'s LLM credential flow —
  the two are intentionally separate. LLM API keys are never written as
  `PENDING_VAULT_` entries and must not be processed by this SOP.
