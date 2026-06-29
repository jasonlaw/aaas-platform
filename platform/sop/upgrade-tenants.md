# SOP: Upgrade All Tenant Containers

## Purpose
Upgrade all active tenants to the latest Docker image after build-image.md completes.

## Steps
1. Confirm: "This will restart all active tenant containers with the new image. Brief downtime per tenant. Proceed? (y/n)"
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`, then read tenants.yaml and list tenants with `status: active`.
3. For each active tenant:
   - ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml` exists; if missing, create it from `/opt/aaas/platform/harness/tenant-harness.yaml.template` using known tenant metadata and mark unknown fields clearly
   - ensure `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md` exists; if missing, create it from `/opt/aaas/platform/harness/ACCEPTANCE.md.template`
   - ensure `/opt/aaas/tenants/{tenant-id}/vault/` exists (tenants onboarded before this feature existed will not have it); if missing, back-fill it without touching any other tenant state:
     ```bash
     mkdir -p /opt/aaas/tenants/{tenant-id}/scripts
     cp /opt/aaas/platform/scripts/tenant/vault-init-tenant.sh /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh
     chmod +x /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh
     TENANT_DIR=/opt/aaas/tenants/{tenant-id} BUSINESS_NAME="{business-name}" \
       /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh {tenant-id}
     ```
     This is safe to re-run even if the vault already exists — it never overwrites existing notes. After backfilling, also add the `vault -> /home/hermes/vault` mount to this tenant's compose service block if it is missing, since older services predate this mount.
   - ensure `/opt/aaas/tenants/{tenant-id}/tenant-policy.yaml` exists (tenants onboarded before the policy framework existed will not have it); if missing, create it from `/opt/aaas/platform/templates/_base/tenant-policy.yaml.template` with `{{TENANT_ID}}` and `{{BUSINESS_NAME}}` filled in
   - re-render the `## Platform rules` and `## Tenant rules` BEGIN/END blocks in `SOUL.md` from `/opt/aaas/platform/policy/platform-policy.yaml` and this tenant's `tenant-policy.yaml`, following the same rendering instruction as onboard-tenant.md step 5/update-tenant.md step 5, so pre-existing tenants pick up policy changes shipped with this platform version
   - backfill: create this tenant's isolated network if it does not exist, and ensure Agent Vault has joined it:
     ```bash
     if ! docker network inspect hermes-{tenant-id}-net >/dev/null 2>&1; then
       docker network create hermes-{tenant-id}-net
       docker network connect hermes-{tenant-id}-net agent-vault
     fi
     ```
     Then update this tenant's compose service block to use `hermes-{tenant-id}-net` instead of the old shared `agent-vault-net`, if it still references the shared network. Declare the network block (`external: true`, `name: hermes-{tenant-id}-net`) at the bottom of docker-compose.yaml if not already present.
   - repair ownership after any edits or file creation: `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
   - `chown -R` does not change file mode, so also repair host-side access for the `docker compose` CLI: `sudo chmod 755 /opt/aaas/tenants/{tenant-id}/` and `sudo chmod 644 /opt/aaas/tenants/{tenant-id}/.env`
   - run `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
   - `docker compose stop hermes_{tenant-id}`
   - `docker compose rm -f hermes_{tenant-id}`
   - `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`
   - verify with `docker ps | grep hermes_{tenant-id}`
   - run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   - update tenants.yaml `last_updated`
4. Report total upgraded, harness pass/warn/fail summaries, tenant-facing risks, and any failures.