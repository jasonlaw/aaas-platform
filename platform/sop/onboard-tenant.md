# SOP: Onboard New Tenant

## Purpose
Provision a new Hermes tenant agent as a Docker container.

## Pre-requisites
- hermes-tenant:latest Docker image built
- Telegram bot token ready
- Tenant LLM API key ready

## Steps
1. Collect tenant information one question at a time: business type, business name, vertical details, location, brand tone, colors, owner profile, Telegram bot token, allowed Telegram user IDs, LLM provider/model, provider-specific API key env var name, and API key value. If a social page blocks unauthenticated access, do not stall; use web search, public review/blog pages, Instagram bios, Google Business snippets, or operator-provided notes as alternate brand sources, and report which sources were used.
2. Show a full confirmation summary and ask: "Proceed with onboarding? (y/n)"
3. Generate tenant ID as a lowercase slug from business name.
4. Create tenant directories under `/opt/aaas/tenants/{tenant-id}/`: `memories`, `skills`, `files/assets`, `files/uploads`, `files/generated`.
5. Render templates into `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `memories/MEMORY.md`, and `memories/USER.md`. Keep `home_chat_id: ""` in `config.yaml`; Telegram routing is restricted by `TELEGRAM_ALLOWED_USERS` in `.env`.
6. Verify `config.yaml` contains `memory.provider: mnemosyne`, `memory_enabled: false`, `user_profile_enabled: false`, and no secrets. Verify `.env` contains the selected provider API key env var, `TELEGRAM_ALLOWED_USERS` as comma-separated numeric IDs, and `MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data`.
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
10. Verify with `docker ps` and `docker logs hermes_{tenant-id} --tail 20`.
11. Install/activate the Mnemosyne Hermes plugin inside the tenant volume, then restart only this tenant:
   `docker exec -e HERMES_HOME=/opt/data hermes_{tenant-id} mnemosyne-hermes install`
   `docker exec hermes_{tenant-id} hermes config set memory.provider mnemosyne`
   `docker exec hermes_{tenant-id} hermes memory setup`
   `docker compose restart hermes_{tenant-id}`
12. Seed Mnemosyne with `memories/MEMORY.md` and `memories/USER.md`. The Mnemosyne CLI command is `store`, not `remember`; if unsure, run `docker exec hermes_{tenant-id} mnemosyne --help`. Because tenant files are owned by UID `10000`, read seed files with `sudo cat` from the host:
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/MEMORY.md)" "tenant-memory" 0.8`
   `docker exec hermes_{tenant-id} mnemosyne store "$(sudo cat /opt/aaas/tenants/{tenant-id}/memories/USER.md)" "tenant-user" 0.8`
   Verify with `docker exec hermes_{tenant-id} hermes memory status`, `docker exec hermes_{tenant-id} hermes mnemosyne stats`, and `docker exec hermes_{tenant-id} hermes mnemosyne inspect "{business-name}"`. If `hermes mnemosyne` is unavailable, try the documented fallback `hermes hermes-mnemosyne`.
13. Add or update the tenant entry in `/opt/aaas/platform/tenants.yaml`.
14. Send the welcome message through the tenant's Telegram bot to every numeric ID in `TELEGRAM_ALLOWED_USERS`. This only succeeds for users who have already opened the bot and sent `/start`; report Telegram `400 Bad Request: chat not found` or `403 Forbidden` as "user must start the bot first":
   `curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="{user-id}" --data-urlencode text="{welcome-message}"`
15. Report tenant ID, container status, Telegram bot link, Mnemosyne activation/seed status, welcome message delivery status per user ID, registry update status, and any alternate brand sources used because a social platform blocked access.
