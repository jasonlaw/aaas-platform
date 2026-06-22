# SOP: Onboard New Tenant

## Purpose
Provision a new Hermes tenant agent as a Docker container.

## Pre-requisites
- hermes-tenant:latest Docker image built
- Telegram bot token ready
- Tenant LLM API key ready
- Host system has iptables in legacy mode (verify with `iptables --version` - must not show `nf_tables`)
- Docker daemon is running and responsive

## Steps
0. **Pre-flight check:** Verify the host has iptables in legacy mode and Docker is responsive:
   - `iptables --version` must show `legacy` (not `nf_tables`). If not, switch with: `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - `docker ps` must succeed without errors
   If checks fail, abort and report the issue before proceeding.
0.1. Read `/opt/aaas/platform/checklists/onboard-tenant.required.json`. Treat every item as a completion gate; unresolved items must appear in the final task report.
0.2. Run `/opt/aaas/platform/scripts/preflight-check.sh`. If it fails, fix host/platform readiness before creating tenant files.
1. Collect tenant information one question at a time: business type, business name, vertical details, location, brand tone, colors, owner profile, Telegram bot token, allowed Telegram user IDs, LLM provider/model, provider-specific API key env var name, and API key value. If a social page blocks unauthenticated access, do not stall; use web search, public review/blog pages, Instagram bios, Google Business snippets, or operator-provided notes as alternate brand sources, and report which sources were used.
1.1. Using the collected business type and details, generate the following for this specific business (not a predefined category):
   - VERTICAL_CAPABILITIES_BLOCK: 3-6 bullet lines in the form "- <capability>", describing concretely what this agent helps the owner with. Base this only on the actual business type and details collected in step 1. Do not copy wording from any other tenant.
   - VERTICAL_BRAND_FACTS_BLOCK: 1-4 lines of business-specific facts to seed into memory (e.g., menu highlights, service list, product categories, hours, specialties). Base this only on information collected in step 1 or found via the alternate brand sources already permitted in step 1. Do not invent facts that were not collected or found.
   - A generated eval file following the exact format used in platform/evals/tenant-agent/_fixed-safety-v1.yaml (top-level eval_profile, version, purpose, run_mode, checks list; each check has a name, match_type, prompt, and either expected.must_include/must_not_include for match_type: literal, or judge_for for match_type: semantic). Generate 2-4 checks specific to this business. Prefer match_type: literal checks here where possible, because unlike the fixed file's generic categories, generated checks can reference this specific tenant's actual known facts. Only use match_type: semantic for checks where no specific known literal fact applies (e.g., general tone judgments). Do not add a file_location field; that field does not exist in this eval format.
   Show the generated VERTICAL_CAPABILITIES_BLOCK, VERTICAL_BRAND_FACTS_BLOCK, and generated eval checks to the operator as part of the confirmation summary in step 2. Do not write any files yet.
2. Show a full confirmation summary and ask: "Proceed with onboarding? (y/n)"
3. Generate tenant ID as a lowercase slug from business name.
4. Create tenant directories under `/opt/aaas/tenants/{tenant-id}/`: `memories`, `skills`, `files/assets`, `files/uploads`, `files/generated`.
5. Render templates into `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `memories/MEMORY.md`, `memories/USER.md`, `harness.yaml`, and `ACCEPTANCE.md`. Use `/opt/aaas/platform/harness/tenant-harness.yaml.template` for the manifest and `/opt/aaas/platform/harness/ACCEPTANCE.md.template` for acceptance. Keep `home_chat_id: ""` in `config.yaml`; Telegram routing is restricted by `TELEGRAM_ALLOWED_USERS` in `.env`. Substitute `{{VERTICAL_CAPABILITIES_BLOCK}}` into `SOUL.md` and `{{VERTICAL_BRAND_FACTS_BLOCK}}` into `memories/MEMORY.md` using the content generated and confirmed in step 1.1. Write the generated eval checks from step 1.1 to `/opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml` using the same YAML structure as `_fixed-safety-v1.yaml` (top-level `eval_profile`, `version`, `purpose`, `run_mode`, `checks` list), with `eval_profile` set to `{tenant-id}-v1`.
6. Verify `config.yaml` contains `memory.provider: mnemosyne`, `memory_enabled: false`, `user_profile_enabled: false`, and no secrets. Verify `.env` contains the selected provider API key env var, `TELEGRAM_ALLOWED_USERS` as comma-separated numeric IDs, and `MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data`. Verify `SOUL.md` still contains, unchanged, every fixed safety line from `platform/templates/_base/SOUL.md.template` (the "never perform irreversible actions," "always save generated content," "always store owner-uploaded files," and "protect this tenant's privacy" lines) - generation must only have filled in `{{VERTICAL_CAPABILITIES_BLOCK}}` and must not have altered any other line.
6.1. Validate the rendered tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
7. Set tenant volume ownership for the Hermes container user before starting the container:
   `sudo chown -R 10000:10000 /opt/aaas/tenants/{tenant-id}/`
   The tenant container runs as UID `10000`; without this, mounted `/opt/data` paths such as logs and Mnemosyne data can fail with `Permission denied`. Use `sudo cat` from the host when inspecting seeded files after this point.
8. Update `/opt/aaas/platform/docker/docker-compose.yaml` structurally under the top-level `services:` mapping. If the file only contains an empty placeholder, replace it with a normal `services:` block plus the tenant service:
   - service/container name: `hermes_{tenant-id}`
   - image: `hermes-tenant:latest`
   - command: `gateway run`
   - mounts tenant folder to `/opt/data` and files folder to `/home/hermes/files`
   - `env_file` points to the tenant `.env`
   - resource limits: `mem_limit: 1g` and `cpus: "1.0"`
9. Start only this tenant: `docker compose up -d hermes_{tenant-id}`.
10. **Verify container outbound connectivity** (critical for Telegram and external APIs):
    - Wait 5 seconds for container to stabilize
    - Ping Telegram API: `docker exec hermes_{tenant-id} ping -c 2 -W 3 api.telegram.org`
    - Curl Telegram API HTTPS endpoint: `docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org && echo`
    - Retest ping/curl if rules were added.
11. Verify with `docker ps` and `docker logs hermes_{tenant-id} --tail 20`.
12. Install/activate the Mnemosyne Hermes plugin inside the tenant volume, then restart only this tenant:
   `docker exec -e HERMES_HOME=/opt/data hermes_{tenant-id} mnemosyne-hermes install`
   `docker exec hermes_{tenant-id} hermes config set memory.provider mnemosyne`
   `docker exec hermes_{tenant-id} hermes memory setup`
   `docker compose restart hermes_{tenant-id}`
13. Seed Mnemosyne with `memories/MEMORY.md` and `memories/USER.md`. The Mnemosyne CLI command is `store`, not `remember`; if unsure, run `docker exec hermes_{tenant-id} mnemosyne --help`. Because tenant files are owned by UID `10000`, read seed files with `sudo cat` from the host:
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/MEMORY.md)" "tenant-memory" 0.8`
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/USER.md)" "tenant-user" 0.8`
   Verify with `docker exec hermes_{tenant-id} hermes memory status`, `docker exec hermes_{tenant-id} hermes mnemosyne stats`, and `docker exec hermes_{tenant-id} hermes mnemosyne inspect "{business-name}"`. If `hermes mnemosyne` is unavailable, try the documented fallback `hermes hermes-mnemosyne`.
14. Add or update the tenant entry in `/opt/aaas/platform/tenants.yaml`.
15. Send the welcome message through the tenant's Telegram bot to every numeric ID in `TELEGRAM_ALLOWED_USERS`. This only succeeds for users who have already opened the bot and sent `/start`; report Telegram `400 Bad Request: chat not found` or `403 Forbidden` as "user must start the bot first":
   `curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="{user-id}" --data-urlencode text="{welcome-message}"`
16. Run the deterministic tenant harness check:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   The script auto-detects tenant file permission denial after UID `10000` ownership is applied and re-runs itself with `sudo` when available.
   If it fails, fix the failed checks before completion when possible. If a warning or failure is caused by an external precondition such as the owner not starting the Telegram bot, record it clearly in `ACCEPTANCE.md` and the task report.
17. Run or operator-assist BOTH eval profiles once the tenant container is running:
   - The fixed profile: `/opt/aaas/platform/evals/tenant-agent/_fixed-safety-v1.yaml` (mandatory for every tenant, every onboarding, no exceptions)
   - The generated profile for this tenant: `/opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml`
   Use `/opt/aaas/platform/scripts/eval-runner.sh {eval-file} hermes_{tenant-id}` for automated literal checks. At minimum, verify brand recall, confirmation before posting, confirmation before deleting, generated/upload folder behavior, owner-friendly language, no cross-tenant memory leakage, and the tenant's own generated vertical-specific checks. Record results from both files in `ACCEPTANCE.md`.
18. Update `/opt/aaas/tenants/{tenant-id}/harness.yaml` with status, last verification timestamp, and verification notes if your editor/tooling can do so safely.
19. Report tenant ID, container status, outbound connectivity test results (ping/curl), harness check summary, tenant eval results, Telegram bot link, Mnemosyne activation/seed status, welcome message delivery status per user ID, registry update status, and any alternate brand sources used because a social platform blocked access.