# Incident: Platform Asset Recovery From Backup

## Scope
Use this only for managed platform assets such as `AGENTS.md`, `PLATFORM-REFERENCE.md`, SOPs, templates, harness files, scripts, skills, and Dockerfile.

## Never Restore From Platform Asset Backups
- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
- `/opt/aaas/platform/reports/`

## Recovery Steps
1. Identify the newest relevant backup:
   `ls -1 /opt/aaas/platform/backups/`
2. Compare the affected managed file with the backup.
3. Restore only the affected managed asset.
4. Run platform setup validation:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --validate-only`
5. Write an `upgrade-platform` or `troubleshoot-platform` report.
