# SOP: Reactivate Tenant

## Steps
1. Ask operator for tenant ID.
2. Verify tenant exists in tenants.yaml with `status: suspended`.
3. Start container:
   `cd /opt/aaas/platform/docker`
   `docker compose up -d hermes_{tenant-id}`
4. Verify running: `docker ps | grep hermes_{tenant-id}`.
5. Update tenants.yaml: `status: active`, clear `suspended_reason`, set `last_updated: {today}`.
6. Send Telegram welcome-back message.
7. Confirm reactivation to operator.
