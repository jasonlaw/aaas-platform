# SOP: Upgrade All Tenant Containers

## Purpose
Upgrade all active tenants to the latest Docker image after build-image.md completes.

## Steps
1. Confirm: "This will restart all active tenant containers with the new image. Brief downtime per tenant. Proceed? (y/n)"
2. Read tenants.yaml and list tenants with `status: active`.
3. For each active tenant:
   - `docker compose stop hermes_{tenant-id}`
   - `docker compose rm -f hermes_{tenant-id}`
   - `docker compose up -d hermes_{tenant-id}`
   - verify with `docker ps | grep hermes_{tenant-id}`
   - update tenants.yaml `last_updated`
4. Report total upgraded and any failures.
