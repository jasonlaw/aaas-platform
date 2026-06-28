# SOP: Deprovision Tenant Vault

## Purpose
Remove a tenant's vault, credentials, and agent token from Agent Vault
during offboarding. Called as a sub-step of offboard-tenant after the
container is stopped and before tenant data is deleted.

## Pre-requisites
- Agent Vault container is running: `docker ps | grep agent-vault`
- `agent-vault` CLI is installed and authenticated: `agent-vault vault list`
- Tenant container is already stopped (offboard-tenant step 5 complete)

## Steps

### 1. Delete the tenant vault
```bash
agent-vault vault delete {tenant-id}-vault
```

This deletes the vault and cascades to all credentials and agent tokens
scoped to it. There is no undo.

Confirm deletion:
```bash
agent-vault vault list
# Expected: {tenant-id}-vault is absent
```

### 2. Verify no orphan tokens remain
```bash
agent-vault agent list --vault {tenant-id}-vault 2>&1 | grep -q "not found" \
  && echo "OK: vault gone" \
  || echo "WARN: vault may still exist"
```

### 3. Confirm to calling SOP
Return control to offboard-tenant. The tenant's proxy token in `.env` will be
deleted as part of the tenant data directory removal in offboard-tenant step 7.

## Notes
- If Agent Vault is unreachable at offboard time, note this in the task report
  and schedule vault cleanup for when the service recovers. The tenant container
  is already stopped, so the orphan vault is inert but should be cleaned up.
- Vault deletion is irreversible. Always confirm the correct tenant ID before running.