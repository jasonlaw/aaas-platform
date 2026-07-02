# SOP: Upgrade All Tenant Containers

## Purpose
Upgrade all active tenants to the latest Docker image after build-image.md completes.

## Steps
1. Confirm: "This will restart tenant containers that actually need it (new image or a config/network backfill applied this run). Brief downtime per affected tenant. Proceed? (y/n)"
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`, then read tenants.yaml and list tenants with `status: active`. Resolve the target image ID once: `docker inspect --format '{{.Id}}' hermes-tenant:latest`.
3. For each active tenant, track a per-tenant `NEEDS_RECREATE` flag (starts `false`; set `true` by any backfill sub-step below that actually changes a file, network, or compose entry for this tenant — not merely by running the idempotent check itself):
   - ensure `/opt/aaas/tenants/{tenant-id}/harness.yaml` exists; if missing, create it from `/opt/aaas/platform/harness/tenant-harness.yaml.template` using known tenant metadata and mark unknown fields clearly
   - ensure `/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md` exists; if missing, create it from `/opt/aaas/platform/harness/ACCEPTANCE.md.template`
   - ensure `/opt/aaas/tenants/{tenant-id}/vault/` exists (tenants onboarded before this feature existed will not have it); if missing, back-fill it without touching any other tenant state:
     ```bash
     mkdir -p /opt/aaas/tenants/{tenant-id}/scripts
     cp /opt/aaas/platform/tenant-hermes/scripts/vault-init-tenant.sh /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh
     chmod +x /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh
     TENANT_DIR=/opt/aaas/tenants/{tenant-id} BUSINESS_NAME="{business-name}" \
       /opt/aaas/tenants/{tenant-id}/scripts/vault-init-tenant.sh {tenant-id}
     ```
     This is safe to re-run even if the vault already exists — it never overwrites existing notes. After backfilling, also add the `vault -> /home/hermes/vault` mount to this tenant's compose service block if it is missing, since older services predate this mount.
   - ensure `/opt/aaas/tenants/{tenant-id}/tenant-policy.yaml` exists (tenants onboarded before the policy framework existed will not have it); if missing, create it from `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template` with `{{TENANT_ID}}` and `{{BUSINESS_NAME}}` filled in
   - ensure `/opt/aaas/tenants/{tenant-id}/scripts/tenant-install.sh`, `reconcile-plugins.sh`, and `tenant-entrypoint.sh` exist (tenants onboarded before this feature existed will not have them); if missing, back-fill per `onboard-tenant.md` step 6.2.1, then update this tenant's compose service `command:` to `/opt/data/scripts/tenant-entrypoint.sh` if it still reads the bare `gateway run` — this sets `NEEDS_RECREATE` for this tenant, since the running container's process is unaffected until it restarts under the new command
   - re-render the `## Platform rules` and `## Tenant rules` BEGIN/END blocks in `SOUL.md` from `/opt/aaas/platform/policy/platform-policy.yaml` and this tenant's `tenant-policy.yaml`, following the same rendering instruction as onboard-tenant.md step 5/update-tenant.md step 5, so pre-existing tenants pick up policy changes shipped with this platform version
   - backfill: create this tenant's isolated network if it does not exist, and ensure the per-tenant forwarding sidecar is connected to it. Agent Vault itself must never join a tenant network directly (its management port `:14321` listens on the same interface as the proxy port and would become reachable from inside the tenant container — this is what the harness's `agent_vault_mgmt_port_not_reachable_from_tenant` check catches):
     ```bash
     if ! docker network inspect hermes-{tenant-id}-net >/dev/null 2>&1; then
       docker network create hermes-{tenant-id}-net
     fi
     if ! docker ps -a --format '{{.Names}}' | grep -qx agent-vault-proxy-{tenant-id}; then
       docker run -d --name agent-vault-proxy-{tenant-id} --restart unless-stopped \
         --network agent-vault-net alpine/socat \
         TCP-LISTEN:14322,fork,reuseaddr TCP:agent-vault:14322
     fi
     docker network connect hermes-{tenant-id}-net agent-vault-proxy-{tenant-id} 2>/dev/null || true
     # Only after the sidecar is confirmed connected: drop Agent Vault's own
     # direct connection left over from before this fix (pre-existing
     # tenants only — `|| true` makes this safe to run even if it was never
     # connected). This is the step that actually closes the management-port
     # hole; the sidecar alone is not sufficient while this connection still
     # exists, since Agent Vault would still be reachable on :14321 the old way.
     docker network disconnect hermes-{tenant-id}-net agent-vault 2>/dev/null || true
     ```
     Then update this tenant's compose service block to use `hermes-{tenant-id}-net` instead of the old shared `agent-vault-net`, if it still references the shared network, and update `HTTP_PROXY`/`HTTPS_PROXY` in `.env` to point at `agent-vault-proxy-{tenant-id}:14322` if either still references `agent-vault:14322` directly. Declare the network block (`external: true`, `name: hermes-{tenant-id}-net`) at the bottom of docker-compose.yaml if not already present.
   - repair ownership after any edits or file creation: `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
   - `chown -R` does not change file mode, so also repair host-side access for the `docker compose` CLI, recursively — a top-level-only chmod misses subdirectories the tenant container creates at runtime, which is exactly the gap that has been leaving tenant directories unreadable after past upgrades: `sudo chmod -R go+rX /opt/aaas/tenants/{tenant-id}/`
   - run `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
   - **Decide whether this tenant actually needs a recreate.** Compare the running container's current image against the target:
     `docker inspect --format '{{.Image}}' hermes_{tenant-id}` vs. the target image ID resolved in step 2.
     If they already match **and** `NEEDS_RECREATE` is still `false` for this tenant (no backfill sub-step changed anything above), this tenant is already fully up to date — skip the recreate entirely, verify with `docker ps | grep hermes_{tenant-id}`, run `check-tenant.sh`, record `skipped_recreate: no changes` in the report, and move to the next tenant. Recreating a container that needs nothing risks losing any state that only lives in the container's writable layer for zero benefit, and this platform's own operating rule is to avoid recreate unless it is a MUST.
     Otherwise (image differs, or a backfill sub-step set `NEEDS_RECREATE`), recreate is required to load the new image and/or the updated file/network state cleanly:
     `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`
     (`--force-recreate` already stops and replaces the container in one step — do not additionally `stop`/`rm -f` first, that only adds extra downtime without changing the outcome.)
   - verify with `docker ps | grep hermes_{tenant-id}`
   - run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   - update tenants.yaml `last_updated`
4. Report total tenants processed, how many were actually recreated vs. skipped (with reason), harness pass/warn/fail summaries, tenant-facing risks, and any failures.