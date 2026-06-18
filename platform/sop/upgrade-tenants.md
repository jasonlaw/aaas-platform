# SOP: Upgrade All Tenant Containers

## Purpose
Upgrade all active tenants to the latest Docker image after build-image.md completes.

## Steps
1. Confirm: "This will restart all active tenant containers with the new image. Brief downtime per tenant. Proceed? (y/n)"
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`, then read tenants.yaml and list tenants with `status: active`.
3. For each active tenant:
   - ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml` exists; if missing, create it from `/opt/aaas/platform/harness/tenant-harness.yaml.template` using known tenant metadata and mark unknown fields clearly
   - ensure `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md` exists; if missing, create it from `/opt/aaas/platform/harness/ACCEPTANCE.md.template`
   - run `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
   - `docker compose stop hermes_{tenant-id}`
   - `docker compose rm -f hermes_{tenant-id}`
   - `docker compose up -d hermes_{tenant-id}`
   - verify with `docker ps | grep hermes_{tenant-id}`
   - run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   - update tenants.yaml `last_updated`
4. Report total upgraded, harness pass/warn/fail summaries, tenant-facing risks, and any failures.
