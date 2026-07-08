# AaaS Platform — Setup to First Tenant Flow
> Platform version: 0.19.2 · Last updated: 2026-07-08

End-to-end reference for a fresh Ubuntu host through to the first running tenant. Each phase maps to a specific script or SOP; the responsible actor (operator or agent) is noted for every step.

---

## Phase 1 — Prerequisites
**Script:** `scripts/setup-prerequisites.sh`
**Actor:** Operator

| Step | What happens |
|------|-------------|
| 1 | Ubuntu packages updated; `curl`, `git`, `build-essential`, `openssh-client`, `python3` installed |
| 2 | Git verified; placeholder global `user.name` / `user.email` set if missing |
| 3 | ED25519 SSH key generated at `~/.ssh/id_ed25519`; SSH agent started; auto-start block written to `~/.bashrc` |
| 4 | `~/.bash_profile` wired to source `~/.bashrc` — ensures nvm and opencode are on PATH in every new terminal, including after `curl \| bash` installs |
| 5 | nvm installed; Node.js LTS installed and set as default |
| 6 | Docker Engine installed; operator added to `docker` group; script re-execs under new group (no logout needed) |
| 7 | iptables switched to legacy mode; Docker restarted |
| 8 | OpenCode installed; `~/.local/bin` and `~/.opencode/bin` prepended to PATH |
| 9 | Agent Vault CLI installed |
| 10 | `/opt/aaas/` folder structure created; operator owns all paths |
| 11 | `tenants.yaml` and `docker-compose.yaml` stubs initialised |

**End state:** All tools installed and on PATH in the current session and in every future terminal.

---

## Phase 2 — Platform Setup
**Script:** `scripts/setup-platform.sh`
**Actor:** Operator

| Step | What happens |
|------|-------------|
| 1 | Prerequisites verified: git, docker, opencode, agent-vault CLI all present and Docker responsive |
| 2 | Assets resolved from local repo clone or downloaded from GitHub archive |
| 3 | All managed platform assets installed: SOPs, scripts, templates, skills, incidents, evals, Dockerfile, policy files |
| 4 | **Watchdog installed** — `loginctl enable-linger` run for the operator user; `sudo aaas-watchdog.sh --install` writes `aaas-watchdog.service` + `aaas-watchdog.timer` to `/etc/systemd/system/`, enables and starts the timer (fires at boot + every 5 minutes) |
| 5 | **Agent Vault setup** — data dir and `docker-compose.yaml` created; master password auto-generated via `openssl rand` and saved to `/opt/aaas/agent-vault/.env` (chmod 600); image pulled; container started; health confirmed within 120s (hard error if not healthy) |
| 6 | Full install validated — all managed assets, content checks, Agent Vault infrastructure |

**End state:** Agent Vault is running and healthy. Watchdog is active and already monitoring it. Platform assets are installed and validated.

> **Retrieve the auto-generated Agent Vault password any time:**
> ```bash
> grep AGENT_VAULT_MASTER_PASSWORD /opt/aaas/agent-vault/.env
> ```

---

## Phase 3 — Open OpenCode
**Actor:** Operator

```bash
cd /opt/aaas/platform && opencode
```

The operator is now talking to the admin Hermes agent. Platform context is loaded automatically from `AGENTS.md` and `PLATFORM-REFERENCE.md`.

---

## Phase 4 — Complete Agent Vault Setup
**SOP:** `sop/setup-agent-vault.md`
**Actor:** Agent (operator asks: *"Complete the Agent Vault setup"*)

| Step | What happens |
|------|-------------|
| 1 | Agent Vault account registered |
| 2 | MITM CA certificate fetched → saved to `docker/agent-vault-ca.pem` |
| 3 | Dockerfile patched to trust the CA (`COPY` + `update-ca-certificates`) |
| 4 | Tenant image built and tagged: `setup-platform.sh --build-image` → `hermes-tenant:latest` + `hermes-tenant:v1.0` |

**End state:** Tenant image exists. Agent Vault MITM proxy is fully operational. Platform is ready for tenant onboarding.

---

## Phase 5 — Onboard First Tenant
**SOP:** `sop/onboard-tenant.md`
**Actor:** Agent (operator asks: *"Onboard a new tenant"*)

### Pre-flight gates (steps 0–0.4)
| Step | What happens |
|------|-------------|
| 0 | iptables legacy mode verified; `docker ps` confirmed responsive |
| 0.1 | Onboarding checklist read from `checklists/onboard-tenant.required.json`; every item treated as a completion gate |
| 0.2 | `preflight-check.sh` run — if `hermes_tenant_image_missing`: agent runs `setup-platform.sh --build-image` autonomously, re-runs preflight, confirms pass before continuing; any other failure stops onboarding |
| 0.3 | Fixed eval primitives file confirmed present |
| 0.4 | Platform policy file confirmed present |

### Collect & generate (steps 1–2)
| Step | What happens |
|------|-------------|
| 1 | Operator interviewed one question at a time: business type, name, vertical details, location, brand tone, Telegram bot token, allowed user IDs, LLM provider/model/key, optional fallback provider |
| 1.1 | Agent checks business website/social links (if given) for brand tone and colour only — no facts extracted |
| 1.2 | Agent generates: `INDUSTRY_CAPABILITIES_BLOCK`, `INDUSTRY_BRAND_FACTS_BLOCK`, tenant eval checks (2–4 literal/semantic), tenant policy rules |
| 2 | Full summary shown to operator → confirmed before any files are written |

### Provision (steps 3–8)
| Step | What happens |
|------|-------------|
| 3 | Tenant ID generated as lowercase slug from business name |
| 4 | Tenant directories created under `/opt/aaas/tenants/{id}/`: `memories/`, `skills/`, `files/assets/`, `files/uploads/`, `files/generated/`, `vault/` |
| 4.1 | Knowledge vault scaffolded empty via `backfill-tenant-vault.sh` → `vault/` with `Customers/`, `Suppliers/`, `Recurring/`, `Reference/` (including an empty `Business Data.md` stub), `.obsidian/`, `README.md`; optional unconfirmed `Reference/Onboarding Notes.md` if a description/links were given |
| 5 | All templates rendered: `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `MEMORY.md`, `USER.md`, `harness.yaml`, `ACCEPTANCE.md`, `tenant-policy.yaml`; generated eval profile written to `tenant-hermes/evals/generated/{id}-v1.yaml` |
| 5.1 | Platform and tenant policy rules injected into `SOUL.md` inside `BEGIN/END` marker blocks |
| 6 | Config verified: `memory.provider: mnemosyne`, `memory_enabled: false`, `user_profile_enabled: false`, no secrets in `config.yaml` |
| 6.1 | `validate-tenant-config.sh {id}` run |
| 6.2 | Runtime scripts installed via `install-tenant-scripts.sh {id}` → `skill-verify.sh`, `tenant-install.sh`, `reconcile-plugins.sh`, `tenant-entrypoint.sh`, `seed-mnemosyne.py` |
| 6.3 | Agent Vault vault provisioned via `provision-tenant-vault.sh` → real API key scrubbed from `.env`, replaced with `routed-via-agent-vault`; proxy vars (`HTTP_PROXY`, `HTTPS_PROXY`, `AGENT_VAULT_TOKEN`, etc.) injected |
| 6.4 | Admin contact skill copied; `ADMIN_HERMES_API_KEY` written to `.env` |
| 7 | Volume ownership repaired: `repair-tenant-ownership.sh {id}` → `chown -R 10000:10000` + `chmod -R go+rX` |
| 8 | Service block appended to `docker-compose.yaml` via `add-tenant-compose-service.sh {id}` — includes watchdog labels, healthcheck, resource limits, network declaration |

### Start & verify (steps 9–19)
| Step | What happens |
|------|-------------|
| 9 | `docker compose up -d hermes_{id}` |
| 10 | Outbound connectivity tested: ping + curl to `api.telegram.org` from inside the container |
| 11 | `docker ps` and `docker logs hermes_{id} --tail 20` checked |
| 12 | Mnemosyne installed and activated inside the tenant volume; container force-recreated |
| 13 | `MEMORY.md` and `USER.md` seeded into Mnemosyne via `seed-mnemosyne.py`; seeding verified with `hermes mnemosyne stats` and `inspect` |
| 14 | Tenant entry added to `tenants.yaml` |
| 15 | Telegram welcome message sent to every allowed user ID |
| 16 | Harness check run: `check-tenant.sh {id}` |
| 17 | Both eval profiles run via `eval-runner.sh`: fixed safety profile + generated tenant profile |
| 18 | `harness.yaml` updated with status and verification timestamp |
| 19 | Task report written covering all outcomes |

**End state:** Tenant container is running, healthy, Mnemosyne-active, and vault-provisioned. Watchdog picks it up automatically on the next 5-minute tick — no registration needed.

---

## Watchdog Coverage Map

```
Priority 0 — agent-vault          (label: aaas.watchdog.priority=0)
             ↓ if down: skip all lower-priority checks this cycle
Priority 1 — admin-hermes         (virtual entity, process-based check)
Priority 5 — hermes_{tenant-id}   (label: aaas.watchdog.priority=5)
             + every future tenant automatically at same priority
```

The watchdog discovers entities by Docker label — no config update needed when a new tenant is added. On failure: 2 restart attempts, then `opencode run --auto` with the entity's incident playbook.

---

## Quick Reference — Key Paths

| Path | What it is |
|------|-----------|
| `/opt/aaas/platform/` | Platform root — SOPs, scripts, templates, assets |
| `/opt/aaas/platform/docker/docker-compose.yaml` | All tenant services |
| `/opt/aaas/platform/tenants.yaml` | Tenant registry (metadata only) |
| `/opt/aaas/platform/reports/` | Task reports + `INDEX.jsonl` |
| `/opt/aaas/platform/watchdog/logs/` | Watchdog run log |
| `/opt/aaas/agent-vault/` | Agent Vault data, compose file, `.env` |
| `/opt/aaas/tenants/{id}/` | Per-tenant volume (configs, memories, files, vault) |
| `/opt/aaas/tenants/{id}/.env` | Tenant runtime env (API key replaced by vault proxy) |
| `/opt/aaas/tenants/{id}/vault/Reference/Business Data.md` | Owner-editable operational details (current prices, hours, menu) |
| `/opt/aaas/tenants/{id}/vault/` | Tenant knowledge vault (Obsidian-compatible) |