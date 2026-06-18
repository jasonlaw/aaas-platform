# Incident: All Tenants Lost Connectivity

## Detection
- Multiple tenants fail Telegram delivery or outbound HTTPS.
- Harness checks warn on `container_outbound_https`.
- Health monitor shows several running containers with failed connectivity.

## Immediate Actions
1. Run `/opt/aaas/platform/scripts/preflight-check.sh`.
2. Check `iptables --version`; it must show `legacy`.
3. Check Docker state with `docker ps`.
4. Check forwarding rules:
   `sudo iptables -L DOCKER-FORWARD -n | head -20`
5. Test one running tenant:
   `docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org && echo`

## Recovery
- If iptables is not legacy, switch alternatives and restart Docker.
- If Docker is down, start Docker and restart only active tenant services.
- If rules are missing after Docker restart, run monitor-health and record the exact missing state before manual changes.

## Post-Incident
- Run `/opt/aaas/platform/scripts/analyze-reports.sh`.
- Write a task report with affected tenants, root cause, recovery action, and prevention signal.
