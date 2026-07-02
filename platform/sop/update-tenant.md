# SOP: Update Tenant Configuration

## Purpose
Update a tenant's config, non-LLM secrets, brand context, owner profile, model, or channels.

**Note on LLM API keys:** LLM API keys are stored exclusively in Agent Vault and are
not updated through this SOP. If a tenant's LLM API key needs to change, contact the
platform operator to update it directly in Agent Vault, or offboard and re-onboard the
tenant using the full onboard-tenant SOP.

## Steps
1. Ask operator for tenant ID.
2. Ask what needs updating: Telegram bot token, brand context, owner profile, model provider/name, channel, generated vertical behavior/eval coverage, or tenant-specific access restrictions (tenant policy).
3. For non-LLM secrets (e.g. Telegram bot token), edit `/opt/aaas/tenants/{id}/.env`.
   Do not edit the LLM provider key entry — it must remain as `routed-via-agent-vault`.
4. For config, edit `/opt/aaas/tenants/{id}/config.yaml`.
5. For brand, owner profile, or generated vertical behavior, update `SOUL.md`, memory seed files, and `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml` only from operator-confirmed facts. Do not alter the fixed conduct language in `SOUL.md` (the "try to work it out yourself," "always save generated content," and "always store owner-uploaded files" lines); generation may only change the business-specific capability block and business facts. Re-seed Mnemosyne via the SDK-based seed script (same one onboarding uses, `/opt/data/scripts/seed-mnemosyne.py` — see onboard-tenant.md step 6.2.2/13; copy it in first if this tenant predates that script). `remember()` always adds, it does not overwrite, so re-seeding adds new memories alongside old ones rather than replacing them — expect the old fact to remain until it decays or is explicitly retired with `hermes mnemosyne forget`/`invalidate` if it's now flatly wrong (e.g. a superseded brand color):
   `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/MEMORY.md fact`
   `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/USER.md preference`
5.1. **For tenant-specific access restrictions (tenant policy):** edit `/opt/aaas/tenants/{tenant-id}/tenant-policy.yaml`, adding or modifying rules in the same shape as a platform-policy.yaml rule (id, category, agent_instruction, eval_checks). Reject any rule that contradicts or widens past a `platform-policy.yaml` rule — tenant policy may only narrow. Re-render the `<!-- BEGIN TENANT RULES -->`/`<!-- END TENANT RULES -->` block in `SOUL.md` from the updated `tenant-policy.yaml`, copying `agent_instruction` verbatim. If `/opt/aaas/platform/policy/platform-policy.yaml` itself changed since this tenant was last onboarded or updated (e.g. after a platform upgrade), also re-render the `<!-- BEGIN PLATFORM RULES -->`/`<!-- END PLATFORM RULES -->` block from the current `platform-policy.yaml`.
6. For new channels, add token to `.env`, add gateway platform block to `config.yaml`, and update channels in tenants.yaml.
7. Ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml`, `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md`, and `/opt/aaas/tenants/{tenant-id}/tenant-policy.yaml` exist. If `harness.yaml` or `ACCEPTANCE.md` is missing, create it from `/opt/aaas/platform/harness/` templates using known tenant metadata and mark unknown fields clearly. If `tenant-policy.yaml` is missing (tenant onboarded before the policy framework existed), create it from `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template` with an empty `rules: []` list, then render the BEGIN/END policy blocks into `SOUL.md` per step 5.1.
7.1. Ensure `/opt/aaas/tenants/{tenant-id}/vault/` exists (tenants onboarded before this feature existed will not have it). If missing, back-fill it:
   ```bash
   /opt/aaas/platform/scripts/backfill-tenant-vault.sh {tenant-id} "{business-name}"
   ```
   Safe to re-run — never overwrites existing notes. Also add the `vault -> /home/hermes/vault` mount to this tenant's compose service block in `docker-compose.yaml` if it is missing.
8. Repair tenant volume ownership after edits or file creation:
   ```bash
   /opt/aaas/platform/scripts/repair-tenant-ownership.sh {tenant-id}
   ```
   Files created with `sudo tee` or a root editor after onboarding can otherwise
   remain root-owned even when the existing volume is correct. Re-check with
   `harness/check-tenant.sh`'s `tenant_volume_host_readable` result.
9. Validate the updated tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
10. Recreate only this tenant's container to guarantee a clean config reload. This is an unattended-forbidden, always-confirm action — `update-tenant` is only ever run interactively (an operator explicitly asked for a change), but the recreate is a distinct disruptive step from the edit itself, so confirm it separately before running it: state plainly that the container will be replaced (brief downtime) to load the `.env`/`config.yaml`/`SOUL.md` changes just made, and get an explicit y/n:
    `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`
    Never use `docker compose restart` for config, secret, or model provider changes - it preserves the running container and in-memory state, so changes may not take effect. Never use `docker compose down` without `--no-deps` and a specific service name - this affects all tenants.
11. Verify running: `docker ps | grep hermes_{tenant-id}`.
12. Run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}` and fix any failed structural checks before completion when possible.
13. If brand context, owner profile, model, channel behavior, generated vertical behavior, or tenant policy changed, run or operator-assist BOTH eval profiles once the tenant container is running: `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml` and `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml`. If a tenant-policy rule added a new `eval_checks` entry, also run that prompt manually against the live container (tenant-policy checks are not in either generated file by default) and record the result in `ACCEPTANCE.md` alongside the two standard profiles. Record fixed safety and generated tenant eval results in `ACCEPTANCE.md`.
14. Update tenants.yaml `last_updated`.
15. Confirm update to operator with harness summary, eval summary if run, and any tenant-facing risk.