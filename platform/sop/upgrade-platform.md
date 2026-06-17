# SOP: Upgrade Platform Setup

## Purpose
Upgrade the installed platform assets to the latest repository version while preserving tenant data, tenant registry, Docker Compose services, and historical reports.

## What This Upgrades
- `/opt/aaas/platform/AGENTS.md`
- `/opt/aaas/platform/VERSION`
- `/opt/aaas/platform/sop/`
- `/opt/aaas/platform/skills/`
- `/opt/aaas/platform/templates/`
- `/opt/aaas/platform/docker/Dockerfile`
- Setup validation behavior from the latest script

## What This Must Preserve
- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
- `/opt/aaas/platform/reports/`
- Existing tenant containers unless a separate tenant/image upgrade is requested

## Steps
1. Read current installed version:
   `cat /opt/aaas/platform/VERSION 2>/dev/null || echo "unknown"`
2. Read recent platform upgrade reports before proceeding:
   `grep '"sop":"upgrade-platform"' /opt/aaas/platform/reports/INDEX.jsonl | tail -n 10`
3. Explain to the operator that this upgrades platform assets only. It does not migrate tenant data, rebuild the tenant Docker image, or restart tenant containers unless explicitly requested.
4. Ask for confirmation: "Proceed with platform upgrade? (y/n)"
5. Run the latest setup installer. On an existing platform it auto-detects upgrade mode and skips image rebuild by default. If the installed `VERSION` already matches the repository `VERSION`, choose whether to continue with a backup, continue without a backup, or cancel:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash`
6. Validate the installed platform:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --validate-only`
7. Read the new installed version:
   `cat /opt/aaas/platform/VERSION`
8. Check that preserved files still exist:
   `test -f /opt/aaas/platform/tenants.yaml`
   `test -f /opt/aaas/platform/docker/docker-compose.yaml`
   `test -f /opt/aaas/platform/reports/INDEX.jsonl`
9. If the new platform version changes the Dockerfile or template behavior and tenant image rebuild is needed, ask the operator before running the build image SOP. Do not rebuild automatically.
10. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `upgrade-platform`.

## Recovery
- The installer backs up managed platform assets under `/opt/aaas/platform/backups/` before versioned upgrades and when the operator chooses the backup option on a same-version rerun.
- If validation fails, inspect the newest backup folder and restore only the affected managed asset. Do not restore `tenants.yaml`, `docker-compose.yaml`, reports, or tenant directories from platform asset backups.

## Rules
- Never delete tenant data during platform upgrade.
- Never overwrite `tenants.yaml` or `docker-compose.yaml` if they already exist.
- Never truncate or rewrite `reports/INDEX.jsonl`.
- Treat tenant Docker image upgrades as separate work through `build-image.md` and `upgrade-tenants.md`.
