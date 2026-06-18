# Incident: Mnemosyne Seed Or Recall Failure

## Detection
- Tenant agent cannot recall brand facts after onboarding or restart.
- `hermes mnemosyne inspect` does not show tenant facts.

## Immediate Actions
1. Validate tenant config.
2. Check `MNEMOSYNE_DATA_DIR` in `.env`.
3. Check `hermes memory status` and Mnemosyne stats.
4. Confirm seed files exist under `/opt/aaas/tenants/{tenant-id}/memories/`.

## Recovery
- Reinstall/activate Mnemosyne plugin from onboarding SOP step 12.
- Re-seed with `mnemosyne store` using `sudo cat` from the host.
- Restart only the affected tenant.
- Run tenant eval checks for brand recall and owner profile.

## Post-Incident
- Update `ACCEPTANCE.md` with the recovery evidence.
- Write root cause and prevention notes in the task report.
