# SOP: Complete Agent Vault Setup

## Purpose
Finish the Agent Vault setup after `setup-platform.sh` has run.
The installer handles directory creation, Compose file, image pull, and container
start (if the master password was already set). This SOP covers the steps that
require operator input or a running container: account registration, MITM CA
fetch, Dockerfile patch, and tenant image rebuild.

Run this SOP once per server, before onboarding the first tenant.

## Pre-requisites
- `setup-platform.sh` has completed successfully
- Agent Vault container is running:
  `docker ps | grep agent-vault`
  If not, set `AGENT_VAULT_MASTER_PASSWORD` in `/opt/aaas/agent-vault/.env`
  and start it:
  `docker compose -f /opt/aaas/agent-vault/docker-compose.yaml up -d agent-vault`
- `agent-vault` CLI is available: `agent-vault --version`

## Steps

### 1. Verify container is healthy
```bash
docker inspect --format='{{.State.Health.Status}}' agent-vault
# Expected: healthy
```
If `starting`, wait 30 seconds and retry. If `unhealthy`, check logs:
```bash
docker logs agent-vault --tail 30
```

### 2. Register the owner account
This is a one-time interactive registration. Follow the prompts:
```bash
agent-vault register --addr http://localhost:14321
agent-vault login --addr http://localhost:14321
```

Your session is saved to `~/.agent-vault/session.json`. Subsequent CLI
commands default to `http://localhost:14321`.

Verify login:
```bash
agent-vault vault list
# Expected: empty list, no error
```

### 3. Fetch the MITM root CA
Tenant containers must trust this CA for TLS interception to work:
```bash
curl -o /opt/aaas/platform/docker/agent-vault-ca.pem \
  http://localhost:14321/v1/mitm/ca.pem
```

Verify it was fetched:
```bash
openssl x509 -in /opt/aaas/platform/docker/agent-vault-ca.pem -noout -subject
# Expected: subject with Agent Vault or similar
```

**Important:** If Agent Vault is ever redeployed with a fresh database (the CA
key regenerates on first boot), repeat this step and rebuild the tenant image.

### 4. Patch the tenant Dockerfile to trust the CA
Edit `/opt/aaas/platform/docker/Dockerfile`:

```dockerfile
FROM nousresearch/hermes-agent:latest

USER root

# Install Agent Vault MITM CA so the proxy can intercept TLS
COPY agent-vault-ca.pem /usr/local/share/ca-certificates/agent-vault-ca.crt
RUN apt-get update -qq && apt-get install -y -qq ca-certificates \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    "mnemosyne-memory[embeddings]" \
    mnemosyne-hermes && \
    chown -R hermes:hermes /opt/hermes/.venv

USER hermes
```

### 5. Rebuild the tenant image
```bash
cd /opt/aaas/platform/docker
docker build -t hermes-tenant:latest .
docker tag hermes-tenant:latest hermes-tenant:v1.0
```

Verify the CA is trusted inside the image:
```bash
docker run --rm hermes-tenant:latest \
  openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
  /usr/local/share/ca-certificates/agent-vault-ca.crt 2>/dev/null \
  && echo "CA trusted" || echo "CA NOT trusted"
```

### 6. Run the health check
```bash
/opt/aaas/platform/scripts/agent-vault-health.sh
# Expected: all PASS, no FAIL
```

### 7. Write task report
Follow `/opt/aaas/platform/sop/write-report.md`. Include:
- Container health status
- CLI registration outcome
- CA fetch and Dockerfile patch confirmed
- Image rebuild status and CA trust verification result
- Any warnings or issues

## Notes
- The master password is stored in `/opt/aaas/agent-vault/.env`. Keep it in a
  secure location outside the server — loss requires a vault reset and
  re-entry of all tenant credentials.
- Back up `/opt/aaas/agent-vault/data/` as part of your server backup schedule.
  The database is encrypted at rest; backing it up does not expose credentials.
- For recovery procedures see `/opt/aaas/platform/incidents/agent-vault-failure.md`.