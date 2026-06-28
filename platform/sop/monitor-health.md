# SOP: Monitor Platform Health

0. Read `/opt/aaas/platform/checklists/monitor-health.required.json`. Treat every item as a completion gate; unresolved items must appear in the final task report.
0.1. **Check Agent Vault health** before checking tenants — if the vault is down, all tenant LLM calls will fail:
   `/opt/aaas/platform/scripts/agent-vault-health.sh`
   If it returns FAIL, follow `/opt/aaas/platform/incidents/agent-vault-failure.md` before proceeding.
   If it returns WARN (e.g. CLI not authenticated), note it in the report but continue.
1. **Verify iptables and Docker state:**
   - Run `/opt/aaas/platform/scripts/preflight-check.sh`. If it fails because Docker is down or iptables is not legacy, stop and fix host readiness before changing tenant state.
   - `iptables --version` must show `legacy`. If not, switch with `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - `docker ps` must succeed without errors
   - Check that `DOCKER-FORWARD` chain exists and contains bridge forwarding rules:
     `sudo iptables -L DOCKER-FORWARD -n | head -10`
     Expected: At least one `ACCEPT` rule for a bridge interface (e.g., `br-*`)
   - If no bridge rules are present, alert operator about potential networking issues. Do not run broad `docker compose down`; restart only affected tenant services after confirming Docker/iptables state.
2. Read tenants.yaml and list tenants with `status: active`.
3. Check Docker status for each active tenant:
   `docker ps --filter name=hermes_{tenant-id} --format "{{.Status}}"`
   Also verify `/opt/aaas/platform/docker/docker-compose.yaml` sets `restart: unless-stopped` for each active `hermes_{tenant-id}` service. If it is missing, report it as a platform prevention issue and ask the operator before editing existing tenant service definitions.
4. Show overall platform view: `docker ps | grep hermes_`.
5. For each running active tenant, verify outbound connectivity:
   - Ping check: `docker exec hermes_{tenant-id} ping -c 1 -W 2 api.telegram.org > /dev/null 2>&1 && echo "OK" || echo "FAILED"`
   - If ping fails, check iptables rules for this tenant's bridge and alert operator
6. For each active tenant with missing files, failed connectivity, container errors, recent restart loops, or operator-reported quality issues, run:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   Include the pass/warn/fail summary in the task report and use it to decide whether the issue is structural, runtime, network, memory, or tenant-facing behavior.
7. Report running tenants and down/erroring tenants.
8. For any down tenant:
   - check logs: `docker logs hermes_{tenant-id} --tail 50`
   - attempt restart: `docker compose up -d hermes_{tenant-id}`
   - if restart fails, alert operator with full error log
   - If restart succeeds, re-run outbound connectivity check (step 5)
9. Summarize total active tenants, connectivity issues, iptables state, restart-policy gaps, harness warnings/failures, and tenant-benefit risks such as memory not seeded, generated files not persisted, or confirmation-before-posting not verified.