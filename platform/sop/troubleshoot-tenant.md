# SOP: Troubleshoot Tenant

## Purpose
Diagnose and recover a tenant issue without full re-onboarding unless the tenant data contract is unrecoverable.

## Steps
1. Ask operator for tenant ID, symptoms, and when the issue started.
2. Read recent matching report entries before acting:
   `grep '"tenant_id":"{tenant-id}"' /opt/aaas/platform/reports/INDEX.jsonl | tail -n 10`
3. Run platform pre-flight:
   `/opt/aaas/platform/scripts/preflight-check.sh`
   If this fails, fix host/platform readiness before changing tenant files.
4. Check tenant registry and compose membership:
   - `grep -n "{tenant-id}" /opt/aaas/platform/tenants.yaml`
   - `grep -n "hermes_{tenant-id}" /opt/aaas/platform/docker/docker-compose.yaml`
5. Run tenant config validation:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
6. Run the tenant harness check:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
7. Check container state:
   - `docker ps -a --filter name=hermes_{tenant-id}`
   - `docker logs hermes_{tenant-id} --tail 80`
8. Check network only if the container is running:
   - `docker exec hermes_{tenant-id} ping -c 1 -W 2 api.telegram.org`
   - `docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org && echo`
9. Check memory only if the container is running:
   - `docker exec hermes_{tenant-id} hermes memory status`
   - `docker exec hermes_{tenant-id} hermes mnemosyne stats`
   - If `hermes mnemosyne` is unavailable, try `hermes hermes-mnemosyne`.
10. Apply the narrowest recovery that matches the evidence. Do not delete tenant data during troubleshooting.
11. Re-run config validation and harness check after the fix.
12. If the issue affected brand recall, confirmation-before-posting, files, uploads, Telegram behavior, or privacy, run or operator-assist the relevant checks from `/opt/aaas/platform/evals/tenant-agent/fnb-marketing-v1.yaml`.
13. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `troubleshoot-tenant`.

## Common Recovery Paths

### Container Missing Or Stopped
- If compose service exists, start only this tenant:
  `cd /opt/aaas/platform/docker && docker compose up -d hermes_{tenant-id}`
- Re-run `docker ps -a --filter name=hermes_{tenant-id}` and the harness check.

### Permission Denied In Logs
- Repair tenant ownership:
  `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
- Restart only this tenant:
  `cd /opt/aaas/platform/docker && docker compose restart hermes_{tenant-id}`

### Invalid Config
- Use `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}` output to identify missing keys.
- Restore required Mnemosyne settings before restarting:
  - `memory.provider: mnemosyne`
  - `memory_enabled: false`
  - `user_profile_enabled: false`
  - `gateway.platforms.telegram.home_chat_id: ""`

### No Outbound Network
- `iptables --version` must show `legacy`.
- If it shows `nf_tables`, switch with:
  `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
- Restart only affected tenant containers after Docker restarts.
- If bridge rules are still missing, run `/opt/aaas/platform/sop/monitor-health.md` and document the result before manual iptables changes.

### Mnemosyne Not Active Or Not Seeded
- Reinstall/activate using onboarding SOP step 12.
- Re-seed with `mnemosyne store`, not `mnemosyne remember`:
  `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/MEMORY.md)" "tenant-memory" 0.8`
  `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/USER.md)" "tenant-user" 0.8`

### Telegram Chat Not Found Or Forbidden
- This usually means the owner has not opened the bot and sent `/start`.
- Do not rotate the bot token unless logs prove the token is invalid.

## Partial Onboarding Recovery
- Before container start: repair generated files, config, compose entry, then continue onboarding.
- After container start but before Mnemosyne seed: run update-tenant memory seeding steps, then harness check.
- After registry/report stage: run harness check and write a corrective task report.
