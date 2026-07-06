# SOP: Troubleshoot Tenant

## Purpose
Diagnose and recover a tenant issue without full re-onboarding unless the tenant data contract is unrecoverable.

## Container Recreate Policy (read before Common Recovery Paths)
- **Unattended (`trigger: watchdog`) runs must never recreate a container — no exception.** `docker compose up --force-recreate`, `docker compose down`, `docker compose rm`, or any other command that stops/removes/replaces the tenant container is forbidden in this session, for every recovery path below, even when the evidence clearly points to it and even though `--auto` would otherwise let the command through unchallenged. If the narrowest fix requires a recreate, apply only the non-recreate portion of that fix (permission repair, starting an already-stopped-but-intact container with plain `docker compose up -d`, diagnosis, log collection), then stop, write the alert file, and write a task report naming the exact recreate command the operator needs to run and why. This is a hard content rule for the agent, not something contingent on a permission prompt.
- **Attended (interactive) runs must explicitly confirm with the operator before any recreate.** Before running a `--force-recreate` in any recovery path below, state plainly what will happen (brief downtime, container replaced) and why it's needed, and get an explicit y/n. Do not fold this into an earlier, unrelated confirmation.

## Steps
1. Ask operator for tenant ID, symptoms, and when the issue started.
2. Read recent matching report entries before acting:
   `grep '"tenant_id":"{tenant-id}"' /opt/aaas/platform/reports/INDEX.jsonl | tail -n 10`
3. Check the knowledge vault for prior history on this tenant or this symptom before treating it as new: follow `/opt/aaas/platform/skills/query-knowledge-vault.md`, starting with `/opt/aaas/platform/vault/Tenants/{tenant-id}.md` if it exists. Skip this step only if the vault does not exist yet.
4. Run platform pre-flight:
   `/opt/aaas/platform/scripts/preflight-check.sh`
   If this fails, fix host/platform readiness before changing tenant files.
5. Check tenant registry and compose membership:
   - `grep -n "{tenant-id}" /opt/aaas/platform/tenants.yaml`
   - `grep -n "hermes_{tenant-id}" /opt/aaas/platform/docker/docker-compose.yaml`
6. Run tenant config validation:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
7. Run the tenant harness check:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
8. Check container state and diagnose log errors using the platform error vocabulary:
   ```bash
   /opt/aaas/platform/scripts/diagnose-tenant-logs.sh {tenant-id}
   ```
   The script checks container status, scans the last 200 log lines against known error patterns (permission, vault, mnemosyne, network, config, plugin, container), and prints each finding with the exact recovery command. Pass a higher tail count for intermittent issues: `diagnose-tenant-logs.sh {tenant-id} 500`. If the script prints `none / no_known_patterns_matched`, read raw logs manually: `docker logs hermes_{tenant-id} --tail 80`
9. Check network only if the container is running:
   - `docker exec hermes_{tenant-id} ping -c 1 -W 2 api.telegram.org`
   - `docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org && echo`
10. Check memory only if the container is running:
   - `docker exec hermes_{tenant-id} hermes memory status`
   - `docker exec hermes_{tenant-id} hermes mnemosyne stats`
   - If `hermes mnemosyne` is unavailable, try `hermes hermes-mnemosyne`.
11. Apply the narrowest recovery that matches the evidence. Do not delete tenant data during troubleshooting. If the evidence so far doesn't point to a narrow fix and continuing means iterating through further hypotheses with no clear bound, stop and check in with the operator before continuing — see PLATFORM-REFERENCE.md's Rules section. This applies unattended too: if unattended and the evidence doesn't point to a narrow, non-recreate fix, stop, write the alert file and a task report describing what was found and what the operator needs to decide, and end the session — do not continue iterating and do not recreate in place of an operator's judgment call. See the Container Recreate Policy above for the specific, separate recreate restriction.
12. Re-run config validation and harness check after the fix.
13. If the issue affected brand recall, confirmation-before-posting, confirmation-before-deleting, files, uploads, Telegram behavior, privacy, or generated industry behavior, run or operator-assist BOTH eval profiles once the tenant container is running: `/opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml` and `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml`. Use `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} {path-to-eval-file}` for automated literal checks and record results in `ACCEPTANCE.md`.
14. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `troubleshoot-tenant`.

## Common Recovery Paths

### Container Missing Or Stopped
- If compose service exists, start only this tenant:
  `cd /opt/aaas/platform/docker && docker compose up -d hermes_{tenant-id}`
- Re-run `docker ps -a --filter name=hermes_{tenant-id}` and the harness check.

### Permission Denied In Logs
- Repair tenant ownership:
  ```bash
  /opt/aaas/platform/scripts/repair-tenant-ownership.sh {tenant-id}
  ```
- The ownership/mode repair takes effect on disk immediately and does not
  itself require a container replace. Force-recreate is only needed if the
  running process still has the old permission error cached (e.g. it opened
  a file handle before the repair and won't retry) — confirm that from
  `docker logs` before recreating rather than recreating by default.
  **Unattended:** never recreate here — apply the repair above, re-check
  logs, and if the error persists, stop and alert per the Container Recreate
  Policy above instead of recreating. **Attended:** confirm with the
  operator per the Container Recreate Policy above, then:
  `cd /opt/aaas/platform/docker && docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`

### Invalid Config
- Use `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}` output to identify missing keys.
- Restore required Mnemosyne settings before restarting:
  - `memory.provider: mnemosyne`
  - `memory_enabled: false`
  - `user_profile_enabled: false`
  - `gateway.platforms.telegram.home_chat_id: ""`
- These are `config.yaml` edits, so per the Container Recreate Policy above a
  recreate is required to load them (Compose/the gateway process only reads
  this file at container creation) — but only after operator confirmation
  when attended, and never at all when unattended (stop and alert instead):
  `cd /opt/aaas/platform/docker && docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`

### No Outbound Network
- `iptables --version` must show `legacy`.
- If it shows `nf_tables`, switch with:
  `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
- Restart only affected tenant containers after Docker restarts.
- If bridge rules are still missing, run `/opt/aaas/platform/sop/monitor-health.md` and document the result before manual iptables changes.

### Mnemosyne Not Active Or Not Seeded
- Check `MNEMOSYNE_DATA_DIR` first — a mismatch between the seeding
  process's data dir/scope and what the agent's live session reads is a
  known Mnemosyne failure mode (facts store without error but never surface
  to recall) and is cheaper to rule out than a full reinstall:
  `docker exec hermes_{tenant-id} sh -lc 'echo $MNEMOSYNE_DATA_DIR'`
  — must equal `/opt/data/mnemosyne/data`, matching `.env`.
- If that's fine, reinstall/activate using onboarding SOP step 12 — that step
  ends in a `--force-recreate`, so the Container Recreate Policy above
  applies: confirm with the operator first if attended; if unattended, run
  only the `docker exec` install/config/seed commands (they don't themselves
  recreate anything) and stop before the final
  `docker compose up --force-recreate` line, then alert and let the operator
  run it.
- Re-seed with the SDK-based seed script, not `mnemosyne store`
  (`/opt/data/scripts/seed-mnemosyne.py` — copy it in from
  `/opt/aaas/platform/tenant-hermes/scripts/seed-mnemosyne.py` first if this
  tenant predates it; see onboard-tenant.md step 6.2.2). It sets
  `scope="global"` explicitly, which the old CLI blob-store never did:
  `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/MEMORY.md fact`
  `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/USER.md preference`

### Tenant-Installed Plugin Missing Or Not Working
- Check `docker exec hermes_{tenant-id} /opt/data/scripts/tenant-install.sh list`
  (or `cat /opt/data/installed-plugins.yaml` directly) first — if the plugin
  isn't listed, it was never installed through `tenant-install.sh` (e.g.
  baked into the image, or the tenant used a raw `pip`/`uv` call directly
  into the container's writable layer, which does not persist and is not
  this script's fault to reconcile).
- To remove a plugin that is broken or no longer wanted, use
  `docker exec hermes_{tenant-id} /opt/data/scripts/tenant-install.sh remove {name}`
  rather than deleting files under `lazy-packages`/`.local/bin` by hand —
  it removes only that package's own files (never a sibling package sharing
  the same `--target` directory) and drops the manifest entry so
  `reconcile-plugins.sh` stops trying to restore it on the next start.
- If it is listed, `reconcile-plugins.sh` already runs automatically on
  every container start via `tenant-entrypoint.sh` — check
  `docker logs hermes_{tenant-id}` for `[reconcile-plugins]` lines to see
  whether it detected the plugin missing/stale and what happened when it
  tried to reinstall. A logged reinstall failure (network issue, package no
  longer available, etc.) needs the same investigation as any other failed
  install, not a recreate.
- To force reconciliation without waiting for the next recreate:
  `docker exec hermes_{tenant-id} /opt/data/scripts/reconcile-plugins.sh`
- If a tenant's compose service still has the old `command: gateway run`
  (onboarded before this feature existed), it never runs
  `reconcile-plugins.sh` at all — back-fill it: copy the three scripts from
  `/opt/aaas/platform/tenant-hermes/scripts/` per `onboard-tenant.md` step
  6.2.1, update the `command:` line to
  `/opt/data/scripts/tenant-entrypoint.sh`, then `--force-recreate` (subject
  to the Container Recreate Policy above).

### Knowledge Vault Missing, Not Mounted, Or Not Owned
- This is a different system from Mnemosyne and from business-data.md - do not
  treat a missing `vault/` directory as a Mnemosyne problem.
- If `/opt/aaas/tenants/{tenant-id}/vault/` is missing, back-fill it (safe to
  re-run, never overwrites existing notes):
  ```bash
  /opt/aaas/platform/scripts/backfill-tenant-vault.sh {tenant-id} "{business-name}"
  ```
- If it exists but the container can't see it, check the compose service has
  the `vault -> /home/hermes/vault` mount. If it was missing and you just
  added it, a recreate is required to pick up the new mount — per the
  Container Recreate Policy above, confirm with the operator if attended;
  never recreate if unattended (stop and alert instead):
  `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`.
- If ownership is wrong, the standard `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
  plus `sudo chmod -R go+rX /opt/aaas/tenants/{tenant-id}/` repair (see
  Permission Denied In Logs above) covers `vault/` too, since both are
  recursive over the whole tenant directory.
- If the owner reports the assistant is writing business facts (current
  prices, menu items) into the vault instead of `business-data.md`, this is a
  SOUL.md prompting issue, not a structural one - confirm `SOUL.md` still
  contains the unmodified three-way decision rule from
  `SOUL.md.template` and escalate to `improve-sop.md` if the model is
  consistently misclassifying facts despite correct prompting.

### Telegram Chat Not Found Or Forbidden
- This usually means the owner has not opened the bot and sent `/start`.
- Do not rotate the bot token unless logs prove the token is invalid.

## Partial Onboarding Recovery
- Before container start: repair generated files, config, compose entry, then continue onboarding.
- After container start but before Mnemosyne seed: run update-tenant memory seeding steps, then harness check.
- After registry/report stage: run harness check and write a corrective task report.