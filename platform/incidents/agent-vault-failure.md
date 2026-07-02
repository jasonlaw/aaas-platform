# Incident: Agent Vault Failure

## Symptoms
- Tenant containers return LLM API errors (`401 Unauthorized`, `502 Bad Gateway`,
  connection refused on `agent-vault:14322`)
- `docker logs hermes_{tenant-id}` shows proxy connection errors
- `/opt/aaas/platform/scripts/agent-vault-health.sh` returns FAIL

## Impact
All tenant agents that route LLM calls through Agent Vault will fail to
respond. Telegram messages will be received but replies will not be generated.
Tenant containers themselves remain running — only outbound API calls are broken.

---

## Diagnosis

### 1. Check container state
```bash
docker ps | grep agent-vault
docker logs agent-vault --tail 50
```

### 2. Run health script
```bash
/opt/aaas/platform/scripts/agent-vault-health.sh
```

### 3. Check data directory
```bash
ls -la /opt/aaas/agent-vault/data/
```
If the `.agent-vault/` subdirectory is missing or empty, the vault database
has been lost (see Recovery B below).

---

## Recovery A — Container stopped or crashed (database intact)

```bash
docker compose -f /opt/aaas/agent-vault/docker-compose.yaml up -d agent-vault
```

Wait for healthy status:
```bash
docker inspect --format='{{.State.Health.Status}}' agent-vault
```

Verify proxy is reachable:
```bash
/opt/aaas/platform/scripts/agent-vault-health.sh
```

No tenant container restart is needed — they will resume proxying once Agent
Vault is healthy again.

---

## Recovery B — Database lost (vault data gone)

This requires re-entering all tenant credentials. Only proceed if the data
directory confirms the database is truly absent.

**Unattended (`trigger: watchdog`) runs must stop here, not proceed into
Recovery B.** Re-entering credentials requires the operator to supply real
API keys and this recovery ends in recreating every active tenant container
— both are things an unattended session must never do on its own, no
exception. Write the alert file and a task report stating the vault database
is lost and Recovery B must be run by the operator, then end the session.

**Attended (interactive) runs:** confirm with the operator before starting
Recovery B (it touches every active tenant) and again before each
tenant's `--force-recreate` below.

1. Re-run the Agent Vault setup SOP:
   `/opt/aaas/platform/sop/setup-agent-vault.md`
   (start from step 3 — directory already exists)

2. For each active tenant, re-run the vault provisioning sub-steps:
   - Create the vault: `agent-vault vault create {tenant-id}-vault`
   - Add the credential (ask operator for the real API key)
   - Mint a new agent token
   - Update `/opt/aaas/tenants/{tenant-id}/.env` with the new `AGENT_VAULT_TOKEN`
   - Recreate the tenant container:
     `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`

   Alternatively, run the full `provision-tenant-vault` SOP for each tenant.

---

## Recovery C — Master password lost

Without the master password the vault database cannot be decrypted.
The vault must be reset (database deleted and re-initialised), then all
credentials re-entered as in Recovery B.

```bash
docker compose -f /opt/aaas/agent-vault/docker-compose.yaml stop agent-vault
rm -rf /opt/aaas/agent-vault/data/.agent-vault/
docker compose -f /opt/aaas/agent-vault/docker-compose.yaml up -d agent-vault
# Then follow Recovery B steps
```

---

## Prevention
- Store the master password in a secure location outside the server
  (password manager, secrets manager, printed and sealed).
- Back up `/opt/aaas/agent-vault/data/` as part of your server backup schedule.
  The database is encrypted at rest; backing it up does not expose credentials.
- The platform backup script at `/opt/aaas/platform/scripts/` does not include
  the vault data directory by default — ensure your server backup covers it.

---

## Post-recovery checklist
- [ ] `agent-vault-health.sh` passes all checks
- [ ] At least one tenant LLM call succeeds end-to-end (ask a test question via Telegram)
- [ ] Task report written per `/opt/aaas/platform/sop/write-report.md`