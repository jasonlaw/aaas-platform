# SOP: Upgrade Platform Setup

## Purpose
Upgrade the installed platform assets to the latest repository version while preserving tenant data, tenant registry, Docker Compose services, and historical reports.

## What This Upgrades
- `/opt/aaas/platform/AGENTS.md`
- `/opt/aaas/platform/VERSION`
- `/opt/aaas/platform/sop/`
- `/opt/aaas/platform/skills/`
- `/opt/aaas/platform/templates/`
- `/opt/aaas/platform/harness/`
- `/opt/aaas/platform/checklists/`
- `/opt/aaas/platform/evals/`
- `/opt/aaas/platform/scripts/`
- `/opt/aaas/platform/incidents/`
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
3. **Verify iptables state before proceeding:**
   - `iptables --version` must show `legacy`. If it shows `nf_tables`, switch with:
     `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - Alert operator that Docker daemon was restarted; all tenant containers must be restarted after the platform upgrade completes
4. Explain to the operator that this upgrades platform assets only. It does not migrate tenant data, rebuild the tenant Docker image, or restart tenant containers unless explicitly requested.
5. Ask for confirmation: "Proceed with platform upgrade? (y/n)"
6. Run the latest setup installer. On an existing platform it auto-detects upgrade mode and skips image rebuild by default. If the installed `VERSION` already matches the repository `VERSION`, choose whether to continue with a backup, continue without a backup, or cancel:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash`
7. Validate the installed platform:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --validate-only`
8. Read the new installed version:
   `cat /opt/aaas/platform/VERSION`
9. Check that preserved files still exist:
   `test -f /opt/aaas/platform/tenants.yaml`
   `test -f /opt/aaas/platform/docker/docker-compose.yaml`
   `test -f /opt/aaas/platform/reports/INDEX.jsonl`
10. **Post-upgrade iptables verification:**
    - `iptables --version` must still show `legacy`. If it reverted to `nf_tables`, switch again and restart Docker
    - `sudo iptables -L DOCKER-FORWARD -n | head -5` should show bridge forwarding rules
    - If rules are missing, run the health monitor SOP to detect and repair
11. If the new platform version changes the Dockerfile or template behavior and tenant image rebuild is needed, ask the operator before running the build image SOP. Do not rebuild automatically.
12. **If Docker daemon was restarted during this upgrade:** Restart all active tenants to ensure they re-establish outbound connectivity:
    `for tenant in $(grep 'status: active' /opt/aaas/platform/tenants.yaml | awk '{print $2}'); do docker compose restart hermes_$tenant; done`
    Then run the health monitor SOP to verify outbound connectivity for all tenants.
13. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `upgrade-platform`.

## Recovery
- The installer backs up managed platform assets under `/opt/aaas/platform/backups/` before versioned upgrades and when the operator chooses the backup option on a same-version rerun.
- If validation fails, inspect the newest backup folder and restore only the affected managed asset. Do not restore `tenants.yaml`, `docker-compose.yaml`, reports, or tenant directories from platform asset backups.

## Rules
- Never delete tenant data during platform upgrade.
- Never overwrite `tenants.yaml` or `docker-compose.yaml` if they already exist.
- Never truncate or rewrite `reports/INDEX.jsonl`.
- Treat tenant Docker image upgrades as separate work through `build-image.md` and `upgrade-tenants.md`.
