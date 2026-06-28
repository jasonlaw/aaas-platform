# SOP: Update Tenant Configuration

## Purpose
Update a tenant's config, non-LLM secrets, brand context, owner profile, model, or channels.

**Note on LLM API keys:** LLM API keys are stored exclusively in Agent Vault and are
not updated through this SOP. If a tenant's LLM API key needs to change, contact the
platform operator to update it directly in Agent Vault, or offboard and re-onboard the
tenant using the full onboard-tenant SOP.

## Steps
1. Ask operator for tenant ID.
2. Ask what needs updating: Telegram bot token, brand context, owner profile, model provider/name, channel, or generated vertical behavior/eval coverage.
3. For non-LLM secrets (e.g. Telegram bot token), edit `/opt/aaas/tenants/{id}/.env`.
   Do not edit the LLM provider key entry — it must remain as `routed-via-agent-vault`.
4. For config, edit `/opt/aaas/tenants/{id}/config.yaml`.
5. For brand, owner profile, or generated vertical behavior, update `SOUL.md`, memory seed files, and `/opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml` only from operator-confirmed facts. Do not alter the fixed safety language in `SOUL.md`; generation may only change the business-specific capability block and business facts. Re-seed Mnemosyne with `store`, not `remember`. Tenant files are owned by UID `10000`, so read from the host with `sudo cat`:
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/MEMORY.md)" "tenant-memory" 0.8`
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/USER.md)" "tenant-user" 0.8`
6. For new channels, add token to `.env`, add gateway platform block to `config.yaml`, and update channels in tenants.yaml.
7. Ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml` and `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md` exist. If either is missing, create it from `/opt/aaas/platform/harness/` templates using known tenant metadata and mark unknown fields clearly.
8. Repair tenant volume ownership after edits or file creation:
   `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
   Files created with `sudo tee` or a root editor after onboarding can otherwise remain root-owned even when the existing volume is correct.
   `chown -R` does not change file mode, so also repair host-side access for the `docker compose` CLI:
   `sudo chmod 755 /opt/aaas/tenants/{tenant-id}/`
   `sudo chmod 644 /opt/aaas/tenants/{tenant-id}/.env`
9. Validate the updated tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
10. Recreate only this tenant's container to guarantee a clean config reload:
    `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`
    Never use `docker compose restart` for config, secret, or model provider changes - it preserves the running container and in-memory state, so changes may not take effect. Never use `docker compose down` without `--no-deps` and a specific service name - this affects all tenants.
11. Verify running: `docker ps | grep hermes_{tenant-id}`.
12. Run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}` and fix any failed structural checks before completion when possible.
13. If brand context, owner profile, model, channel behavior, or generated vertical behavior changed, run or operator-assist BOTH eval profiles once the tenant container is running: `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/evals/tenant-agent/_fixed-safety-v1.yaml` and `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml`. Record fixed safety and generated tenant eval results in `ACCEPTANCE.md`.
14. Update tenants.yaml `last_updated`.
15. Confirm update to operator with harness summary, eval summary if run, and any tenant-facing risk.