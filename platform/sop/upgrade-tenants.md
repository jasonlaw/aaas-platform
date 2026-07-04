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

   Stop and report if a tenant prints `FAIL` — do not continue to the next tenant
   without resolving it, as a failed ownership repair or network step can leave the
   tenant in a partially-upgraded state.

   Note: if a tenant's compose service still references the old shared
   `agent-vault-net` instead of its per-tenant `hermes-{tenant-id}-net`, the
   script flags this but cannot safely rewrite the compose file automatically —
   update the network reference and `HTTP_PROXY`/`HTTPS_PROXY` in `.env` manually
   for that tenant before its next recreate.

3.1. **Re-render SOUL.md policy blocks for each active tenant** (the script does not do this). For each tenant, render every rule's `agent_instruction` from `platform-policy.yaml` and the tenant's `tenant-policy.yaml` as bullet points inside the `<!-- BEGIN PLATFORM RULES -->`/`<!-- BEGIN TENANT RULES -->` marker blocks in `SOUL.md`, copying `agent_instruction` text verbatim. This is required so pre-existing tenants pick up policy changes shipped with this platform version. The `upgrade-tenant.sh` script sets `NEEDS_RECREATE=true` when it backfills anything, but SOUL.md changes also require a recreate — confirm each affected tenant's container was or will be recreated (the script handles this if any change was detected; if SOUL.md was the only change for a given tenant, run `docker compose -f /opt/aaas/platform/docker/docker-compose.yaml up --force-recreate --no-deps -d hermes_{tenant-id}` manually after confirming with the operator).
4. Report total tenants processed, how many were actually recreated vs. skipped (with reason), harness pass/warn/fail summaries, tenant-facing risks, and any failures.