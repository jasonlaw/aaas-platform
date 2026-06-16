# SOP: Monitor Platform Health

## Steps
1. Read tenants.yaml and list tenants with `status: active`.
2. Check Docker status for each active tenant:
   `docker ps --filter name=hermes_{tenant-id} --format "{{.Status}}"`
3. Show overall platform view: `docker ps | grep hermes_`.
4. Report running tenants and down/erroring tenants.
5. For any down tenant:
   - check logs: `docker logs hermes_{tenant-id} --tail 50`
   - attempt restart: `docker compose up -d hermes_{tenant-id}`
   - if restart fails, alert operator with full error log
6. Summarize total active tenants and issues found.
