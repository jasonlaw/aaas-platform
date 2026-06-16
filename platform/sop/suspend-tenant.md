# SOP: Suspend Tenant

## Purpose
Temporarily stop a tenant's Hermes container while preserving data.

## Steps
1. Ask operator for tenant ID and suspension reason.
2. Confirm: "This will stop {tenant-name}'s agent. Proceed? (y/n)"
3. Stop container:
   `cd /opt/aaas/platform/docker`
   `docker compose stop hermes_{tenant-id}`
4. Update tenants.yaml: `status: suspended`, `suspended_reason: {reason}`, `last_updated: {today}`.
5. Send Telegram pause message to tenant.
6. Confirm suspension to operator.

## Note
Container is stopped but not removed. Use offboard-tenant.md for permanent removal only.
