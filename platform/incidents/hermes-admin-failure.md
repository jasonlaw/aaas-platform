# Incident: Hermes Admin Agent Failure

## Symptoms
- Watchdog alert file present at `/opt/aaas/platform/reports/admin-hermes-ALERT.txt`
- Dashboard at `http://127.0.0.1:9119` is unreachable
- `pgrep -f "hermes.*dashboard"` returns no results
- Watchdog log at `/opt/aaas/platform/logs/aaas-watchdog.log` shows restart
  failures for `admin-hermes`

## Impact
Hermes admin being down does not affect running tenant agents — they operate
independently in their Docker containers. Impact is limited to:
- Bidirectional channel between admin and tenants is unavailable
- Admin-initiated operations via Hermes dashboard are unavailable
- OpenCode remains fully functional for all operator-driven SOP work

---

## This Playbook Is Used By

- **The watchdog** (`aaas-watchdog.sh`, the same generic watchdog that also
  covers Agent Vault and tenant containers) invokes OpenCode with a prompt
  referencing this file when admin Hermes's automatic restart fails.
- **OpenCode** reads this file to diagnose and recover without human involvement
  wherever possible.
- **The human operator** reads the Reports section and follows escalation steps
  when OpenCode sets status to `NEEDS_HUMAN`.

---

## Diagnosis

### 1. Check process and dashboard

```bash
pgrep -f "hermes.*dashboard" && echo "process running" || echo "process not found"
curl -sf http://127.0.0.1:9119/health && echo "dashboard responsive" || echo "dashboard not responding"
```

### 2. Check Hermes admin log

```bash
tail -50 /opt/aaas/platform/logs/hermes-admin.log
```

### 3. Check Agent Vault (proxy dependency)

```bash
/opt/aaas/platform/scripts/agent-vault-health.sh
```

If Agent Vault is down, Hermes admin will fail all LLM calls after startup.
Fix Agent Vault first using `/opt/aaas/platform/incidents/agent-vault-failure.md`,
then return here.

### 4. Check .env integrity

```bash
# Placeholder must be set — never a real key
grep "routed-via-agent-vault" /opt/aaas/platform/admin/.env && echo "OK: placeholder" || echo "FAIL: placeholder missing"
# Proxy config must be present
grep "HTTP_PROXY" /opt/aaas/platform/admin/.env && echo "OK: proxy" || echo "FAIL: proxy missing"
# SSL cert file must be set
grep "SSL_CERT_FILE" /opt/aaas/platform/admin/.env && echo "OK: SSL_CERT_FILE" || echo "FAIL: SSL_CERT_FILE missing"
```

### 5. Check host CA trust

```bash
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
  /usr/local/share/ca-certificates/agent-vault-ca.crt 2>/dev/null \
  && echo "CA trusted" || echo "FAIL: CA not trusted"
```

---

## Recovery A — Process crashed, config intact

```bash
pkill -f "hermes.*dashboard" 2>/dev/null || true
sleep 2
cd /opt/aaas/platform/admin
set -a; . ./.env; set +a
nohup hermes dashboard --no-open \
  >> /opt/aaas/platform/logs/hermes-admin.log 2>&1 &
```

Wait up to 15 seconds for the dashboard to become responsive:

```bash
for i in $(seq 1 8); do
  curl -sf http://127.0.0.1:9119/ >/dev/null 2>&1 && echo "OK: dashboard up" && break
  sleep 2
done
```

Run a proxy verification probe to confirm LLM calls work:

```bash
cd /opt/aaas/platform/admin
set -a; . ./.env; set +a
hermes -z "Reply with the single word: PROXY_OK"
# Expected: response containing PROXY_OK
```

---

## Recovery B — Agent Vault token expired or revoked

Symptoms: Hermes starts but LLM calls fail with 407 or 401.

```bash
# Mint a new admin agent token
ADMIN_VAULT_TOKEN=$(agent-vault agent create \
  --vault admin-vault:proxy \
  --name hermes_admin \
  --token-only)

# Update .env with new token
sed -i "s|^HTTP_PROXY=.*|HTTP_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322|" \
  /opt/aaas/platform/admin/.env
sed -i "s|^HTTPS_PROXY=.*|HTTPS_PROXY=http://${ADMIN_VAULT_TOKEN}@localhost:14322|" \
  /opt/aaas/platform/admin/.env
sed -i "s|^AGENT_VAULT_TOKEN=.*|AGENT_VAULT_TOKEN=${ADMIN_VAULT_TOKEN}|" \
  /opt/aaas/platform/admin/.env
```

Then restart as in Recovery A and re-run the proxy probe.

---

## Recovery C — Host CA trust lost (after OS update or cert store reset)

Symptoms: Hermes starts but LLM calls fail with SSL certificate errors.

```bash
sudo cp /opt/aaas/platform/docker/agent-vault-ca.pem \
  /usr/local/share/ca-certificates/agent-vault-ca.crt
sudo update-ca-certificates
```

Verify:

```bash
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
  /usr/local/share/ca-certificates/agent-vault-ca.crt 2>/dev/null \
  && echo "CA trusted" || echo "FAIL"
```

Restart Hermes admin (Recovery A) and re-run proxy probe.

---

## Recovery D — .env proxy config missing or corrupted

Symptoms: Hermes starts but .env is missing HTTP_PROXY or SSL_CERT_FILE.

Re-run Steps 5.5 and 5.6 of `/opt/aaas/platform/skills/setup-admin-hermes.md`
to re-inject the proxy config. You will need the admin vault token:

```bash
# Get the existing token (if agent still registered)
agent-vault agent list --vault admin-vault
# If token is lost, mint a new one (Recovery B above)
```

---

## When To Stop and Escalate to Human (NEEDS_HUMAN)

Set report status to `NEEDS_HUMAN` and stop if any of the following are true:

- Agent Vault database is lost or corrupted (Recovery B in agent-vault-failure.md)
- `admin-vault` does not exist in Agent Vault and the real API key is not available
  to re-provision (operator must supply the key)
- The `agent-vault-ca.pem` file is missing and Agent Vault must be redeployed
  with a fresh database (operator decision required)
- Hermes binary or venv is corrupt and reinstallation is needed but the operator
  has not confirmed it is safe to overwrite the existing install
- Any action would require writing a real API key to disk

In all these cases, write a full diagnostic report explaining:
- What was checked (exact commands and output)
- What was attempted
- Exactly what is blocking automated recovery
- What the operator needs to provide or decide to unblock it

---

## Post-Recovery Checklist

- [ ] `pgrep -f "hermes.*dashboard"` shows a running process
- [ ] Dashboard at `http://127.0.0.1:9119` is responsive
- [ ] Proxy probe (`hermes -z "Reply with the single word: PROXY_OK"`) succeeds
- [ ] Watchdog alert file removed: `rm -f /opt/aaas/platform/reports/admin-hermes-ALERT.txt`
- [ ] Task report written per `/opt/aaas/platform/sop/write-report.md`
- [ ] Watchdog timer still active: `systemctl status aaas-watchdog.timer`
