# Troubleshooting Guide

Use this guide when a tenant is unhealthy and the answer is not obvious from the normal SOP.

## First Checks
1. Run `/opt/aaas/platform/scripts/preflight-check.sh`.
2. Run `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`.
3. Run `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`.
4. Review `docker logs hermes_{tenant-id} --tail 80`.

## Common Issues

### Docker Not Reachable
- Symptom: `Cannot connect to the Docker daemon`.
- Fix: start Docker, then rerun pre-flight.
- Prevention: ensure `systemctl is-enabled docker` reports `enabled`; keep the `.bashrc` fallback for non-systemd hosts documented in prerequisites.

### Container Permission Denied
- Symptom: logs mention permission errors under `/opt/data`, logs, sessions, or Mnemosyne.
- Fix: `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`.
- Then restart only that tenant.

### Network Fails From Container
- Symptom: ping or curl to `api.telegram.org` fails from inside the tenant container.
- First check: `iptables --version` must show `legacy`.
- If not legacy, switch iptables alternatives and restart Docker.
- After Docker restart, restart only affected active tenants and rerun health checks.

### Telegram Welcome Fails
- `chat not found` or `403 Forbidden` usually means the owner has not opened the bot and sent `/start`.
- Ask the owner to start the bot before retrying welcome delivery.

### Mnemosyne Does Not Recall Brand Context
- Confirm `config.yaml` uses `provider: mnemosyne` and native memory is disabled.
- Check `hermes memory status` and Mnemosyne stats inside the container.
- Re-seed from `memories/MEMORY.md` and `memories/USER.md` with `mnemosyne store`.

### Tenant Agent Gives Generic Answers
- Check `SOUL.md` contains the business name, brand tone, privacy rule, and generated/upload file rules.
- Confirm Mnemosyne seed was installed and inspectable.
- Run the tenant eval profile and update `ACCEPTANCE.md`.

## Re-Onboard Or Patch?
- Patch when tenant files, compose service, and registry entry still exist.
- Patch when the issue is permissions, config drift, missing memory seed, or container restart.
- Re-onboard only when the tenant directory was deleted or the operator explicitly wants to replace the tenant setup.
- Never delete tenant data during troubleshooting without explicit typed confirmation.
