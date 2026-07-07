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

### Docker Permission Denied During Fresh Install (`/var/run/docker.sock`)
- Symptom: `Got permission denied while trying to connect to the Docker daemon socket` during `setup.sh` on a machine where Docker was just installed by the same script.
- Cause: `sudo usermod -aG docker $USER` was run but group changes require a new login session to take effect. Prior to 0.15.4, the script did not compensate for this.
- Fix (0.15.4+): the script automatically re-execs itself via `sg docker` after adding the user to the group — no logout or manual step required.
- Fix (if running an older version): run `newgrp docker` then re-run `setup.sh`, or log out and back in before re-running.
- Verification: `id -Gn | grep docker` should include `docker` before any Docker command is attempted.

### Container Permission Denied
- Symptom: logs mention permission errors under `/opt/data`, logs, sessions, or Mnemosyne.
- Fix: `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`.
- Then restart only that tenant.

### Network Fails From Container
- Symptom: ping or curl to `api.telegram.org` fails from inside the tenant container.
- First check: `iptables --version` must show `legacy`. If not, switch
  iptables alternatives and restart Docker.
- If iptables is already legacy and the container is on a custom bridge
  network (e.g. `agent-vault-net`), this is the nftables gap below, not an
  iptables mode issue — see "Docker 29.x Custom Bridge Network Has No
  Internet (nftables gap)".
- After any Docker restart, restart only affected active tenants and rerun health checks.

### Docker 29.x Custom Bridge Network Has No Internet (nftables gap)
- Applies to any host running Docker 29.x, not only Docker Desktop/WSL2 —
  including a plain native Linux install. Setting `iptables-legacy` does
  not prevent or fix this; Docker manages its own nftables ruleset for
  bridge networks independently of the iptables alternative.
- Symptom: `docker exec <container> ping 1.1.1.1` (or any external host)
  times out from a custom bridge network (e.g. `agent-vault-net`), and LLM
  calls through the Agent Vault MITM proxy fail with `HTTP 502 Bad Gateway`
  after a ~12-second timeout, even though the proxy's CONNECT tunnel itself
  establishes fine.
- Cause: Docker 29.x's nftables backend only auto-adds three rules for the
  default `docker0` bridge — a `DOCKER-FORWARD` accept rule for outbound
  traffic, a `DOCKER-CT` established/related accept rule for return
  traffic, and a `POSTROUTING` masquerade rule — and does not add the
  equivalent rules for any custom bridge network. Without them the
  nftables `FORWARD` chain (policy DROP) drops the container's packets
  before they reach the proxy or the internet.
- Check and fix (covers all custom bridge networks on the host):
  ```bash
  sudo /opt/aaas/platform/scripts/fix-docker-nftables.sh --check
  sudo /opt/aaas/platform/scripts/fix-docker-nftables.sh --apply
  ```
  Verify with `docker exec <container> ping -c1 1.1.1.1` and re-test the
  proxy call.
- Make it permanent: these rules are lost on host reboot and on Docker
  daemon restart. Run this once per host:
  ```bash
  sudo /opt/aaas/platform/scripts/fix-docker-nftables.sh --install
  ```
  This installs and enables `aaas-fix-docker-nft.service`, which reapplies
  the rules every time `docker.service` starts.

### Telegram Welcome Fails
- `chat not found` or `403 Forbidden` usually means the owner has not opened the bot and sent `/start`.
- Ask the owner to start the bot before retrying welcome delivery.

### Mnemosyne Does Not Recall Brand Context
- Check `MNEMOSYNE_DATA_DIR` inside the container matches `.env` first — a
  scope/data-dir mismatch is a known way for a seed to report success but
  never surface to recall.
- Confirm `config.yaml` uses `provider: mnemosyne` and native memory is disabled.
- Check `hermes memory status` and Mnemosyne stats inside the container.
- Re-seed from `memories/MEMORY.md` and `memories/USER.md` with
  `/opt/data/scripts/seed-mnemosyne.py` (not `mnemosyne store` — see
  mnemosyne-seed-corruption.md).

### Tenant Agent Gives Generic Answers
- Check `SOUL.md` contains the business name, brand tone, privacy rule, and generated/upload file rules.
- Confirm Mnemosyne seed was installed and inspectable.
- Run the tenant eval profile and update `ACCEPTANCE.md`.

## Re-Onboard Or Patch?
- Patch when tenant files, compose service, and registry entry still exist.
- Patch when the issue is permissions, config drift, missing memory seed, or container restart.
- Re-onboard only when the tenant directory was deleted or the operator explicitly wants to replace the tenant setup.
- Never delete tenant data during troubleshooting without explicit typed confirmation.
