# SOP: Upgrade All Tenant Containers

## Purpose
Upgrade all active tenants to the latest Docker image after build-image.md completes.

## Steps
1. Confirm: "This will restart tenant containers that actually need it (new image or a config/network backfill applied this run). Brief downtime per affected tenant. Proceed? (y/n)"
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`, then read tenants.yaml and list tenants with `status: active`. Resolve the target image ID once: `docker inspect --format '{{.Id}}' hermes-tenant:latest`.
3. For each active tenant, call the per-tenant upgrade script with the target image ID resolved in step 2:
   ```bash
   /opt/aaas/platform/scripts/upgrade-tenant.sh {tenant-id} {target-image-id}
   ```
   The script runs all backfill sub-steps idempotently (harness.yaml, ACCEPTANCE.md,
   knowledge vault, tenant-policy.yaml, runtime scripts, isolated network and
   forwarding sidecar, ownership repair via `repair-tenant-ownership.sh`, config validation), tracks a
   `NEEDS_RECREATE` flag internally, compares running image ID against the target
   (ID vs ID, not tag vs tag), and prints `RECREATED`, `SKIPPED`, or `FAIL` per
   tenant.

   The script also **re-renders `SOUL.md` policy blocks** automatically on every run.
   Only the content between the `<!-- BEGIN PLATFORM RULES -->`/`<!-- END PLATFORM RULES -->`
   and `<!-- BEGIN TENANT RULES -->`/`<!-- END TENANT RULES -->` marker pairs is
   updated — all other `SOUL.md` content (capabilities block, brand tone, conduct
   lines) is left exactly as written at onboarding. Because `SOUL.md` is
   volume-mounted, an updated file is visible to the container on its next restart
   without a forced recreate — `NEEDS_RECREATE` is not set for this change alone.
   If a recreate happens for another reason (image diff, backfill), the updated
   SOUL.md is picked up as part of that restart automatically.

   **`MEMORY.md` and `USER.md` are never modified by this script.** These files are
   maintained at runtime by the tenant agent (Mnemosyne). Overwriting them during
   an upgrade would destroy accumulated tenant-specific facts and preferences.
   To update brand seed facts for an existing tenant, edit `memories/MEMORY.md`
   directly on the host and re-seed via `seed-mnemosyne.py` — do not re-run
   onboarding steps that overwrite the file.

   Stop and report if a tenant prints `FAIL` — do not continue to the next tenant
   without resolving it, as a failed ownership repair or network step can leave the
   tenant in a partially-upgraded state.

   Note: if a tenant's compose service still references the old shared
   `agent-vault-net` instead of its per-tenant `hermes-{tenant-id}-net`, the
   script flags this but cannot safely rewrite the compose file automatically —
   update the network reference and `HTTP_PROXY`/`HTTPS_PROXY` in `.env` manually
   for that tenant before its next recreate.
4. Report total tenants processed, how many were actually recreated vs. skipped (with reason), harness pass/warn/fail summaries, tenant-facing risks, and any failures.