# SOP: Monitor Platform Health

## Steps
1. **Verify iptables and Docker state:**
   - `iptables --version` must show `legacy`. If not, switch with `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - `docker ps` must succeed without errors
   - Check that `DOCKER-FORWARD` chain exists and contains bridge forwarding rules:
     `sudo iptables -L DOCKER-FORWARD -n | head -10`
     Expected: At least one `ACCEPT` rule for a bridge interface (e.g., `br-*`)
   - If no bridge rules are present, alert operator about potential networking issues
2. Read tenants.yaml and list tenants with `status: active`.
3. Check Docker status for each active tenant:
   `docker ps --filter name=hermes_{tenant-id} --format "{{.Status}}"`
4. Show overall platform view: `docker ps | grep hermes_`.
5. For each running active tenant, verify outbound connectivity:
   - Ping check: `docker exec hermes_{tenant-id} ping -c 1 -W 2 api.telegram.org > /dev/null 2>&1 && echo "OK" || echo "FAILED"`
   - If ping fails, check iptables rules for this tenant's bridge and alert operator
6. Report running tenants and down/erroring tenants.
7. For any down tenant:
   - check logs: `docker logs hermes_{tenant-id} --tail 50`
   - attempt restart: `docker compose up -d hermes_{tenant-id}`
   - if restart fails, alert operator with full error log
   - If restart succeeds, re-run outbound connectivity check (step 5)
8. Summarize total active tenants, connectivity issues, and iptables state.
