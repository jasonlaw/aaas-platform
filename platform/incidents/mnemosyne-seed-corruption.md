# Incident: Mnemosyne Seed Or Recall Failure

## Detection
- Tenant agent cannot recall brand facts after onboarding or restart.
- `hermes mnemosyne inspect` does not show tenant facts.

## Immediate Actions
1. Check `MNEMOSYNE_DATA_DIR` matches inside the container and in `.env` —
   scope/data-dir mismatch between the seeding process and the agent's live
   session is a known way for a store to report success but never recall
   (see troubleshoot-tenant.md's "Mnemosyne Not Active Or Not Seeded").
2. Validate tenant config.
3. Check `hermes memory status` and Mnemosyne stats.
4. Confirm seed files exist under `/opt/aaas/tenants/{tenant-id}/memories/`.

## Recovery
- Reinstall/activate Mnemosyne plugin from onboarding SOP step 12.
- Re-seed with `/opt/data/scripts/seed-mnemosyne.py` (SDK-based, sets
  `scope="global"`, one memory per fact) — not `mnemosyne store`/`sudo cat`,
  which this incident's original seeding used. See troubleshoot-tenant.md
  for the exact commands.
- Restart only the affected tenant.
- Run tenant eval checks for brand recall and owner profile.

## Post-Incident
- Update `ACCEPTANCE.md` with the recovery evidence.
- Write root cause and prevention notes in the task report.
