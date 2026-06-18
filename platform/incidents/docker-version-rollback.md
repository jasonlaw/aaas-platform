# Incident: Docker Version Breaks Tenant Networking

## Detection
- Docker was upgraded shortly before tenant connectivity or startup failures.
- `docker version` changed since the last successful health check.

## Immediate Actions
1. Capture `docker version` and `iptables --version`.
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`.
3. Confirm whether failures affect one tenant or all tenants.

## Recovery Options
- Prefer fixing iptables mode and restarting Docker before rolling Docker back.
- If rollback is required, follow the host OS package manager rollback process and preserve `/opt/aaas`.
- After rollback or Docker restart, restart active tenant services individually and run monitor-health.

## Post-Incident
- Record Docker versions before and after.
- Add an improvement signal if setup validation should pin or warn on a Docker version.
