# SOP: Offboard Tenant

## Warning
Destructive and irreversible.

## Steps
1. Ask operator for tenant ID.
2. Show tenant details from tenants.yaml.
3. Confirm: "Type the tenant ID to permanently delete all data:"
4. If confirmation does not exactly match, abort immediately.
5. Stop and remove container:
   `cd /opt/aaas/platform/docker`
   `docker compose stop hermes_{tenant-id}`
   `docker compose rm -f hermes_{tenant-id}`
6. Remove tenant service from docker-compose.yaml.
7. Delete `/opt/aaas/tenants/{tenant-id}` only after exact typed confirmation.
8. Update tenants.yaml: `status: offboarded`, `last_updated: {today}`.
9. Confirm offboarding and deletion to operator.
