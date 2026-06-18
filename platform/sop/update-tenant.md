# SOP: Update Tenant Configuration

## Purpose
Update a tenant's config, secrets, brand context, owner profile, model, or channels.

## Steps
1. Ask operator for tenant ID.
2. Ask what needs updating: LLM API key, Telegram bot token, brand context, owner profile, model provider/name, or new channel.
3. For secrets, edit `/opt/aaas/tenants/{id}/.env`.
4. For config, edit `/opt/aaas/tenants/{id}/config.yaml`.
5. For brand or owner profile, update memory seed files and re-seed Mnemosyne with `store`, not `remember`. Tenant files are owned by UID `10000`, so read from the host with `sudo cat`:
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/MEMORY.md)" "tenant-memory" 0.8`
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/USER.md)" "tenant-user" 0.8`
6. For new channels, add token to `.env`, add gateway platform block to `config.yaml`, and update channels in tenants.yaml.
7. Ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml` and `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md` exist. If either is missing, create it from `/opt/aaas/platform/harness/` templates using known tenant metadata and mark unknown fields clearly.
8. Repair tenant volume ownership after edits or file creation:
   `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
   Files created with `sudo tee` or a root editor after onboarding can otherwise remain root-owned even when the existing volume is correct.
9. Validate the updated tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
10. Restart only this tenant: `docker compose restart hermes_{tenant-id}`.
11. Verify running: `docker ps | grep hermes_{tenant-id}`.
12. Run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}` and fix any failed structural checks before completion when possible.
13. If brand context, owner profile, model, or channel behavior changed, run or operator-assist the relevant checks from `/opt/aaas/platform/evals/tenant-agent/fnb-marketing-v1.yaml` and update `ACCEPTANCE.md` with results.
14. Update tenants.yaml `last_updated`.
15. Confirm update to operator with harness summary, eval summary if run, and any tenant-facing risk.
