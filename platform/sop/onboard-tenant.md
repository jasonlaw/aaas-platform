# SOP: Onboard New Tenant

## Purpose
Provision a new Hermes tenant agent as a Docker container.

## Pre-requisites
- hermes-tenant:latest Docker image built
- Telegram bot token ready
- Tenant LLM API key ready

## Steps
1. Collect tenant information one question at a time: business type, business name, vertical details, location, brand tone, colors, owner profile, Telegram bot token, allowed Telegram user IDs, LLM provider/model/API key.
2. Show a full confirmation summary and ask: "Proceed with onboarding? (y/n)"
3. Generate tenant ID as a lowercase slug from business name.
4. Create tenant directories under `/opt/aaas/tenants/{tenant-id}/`: `memories`, `skills`, `files/assets`, `files/uploads`, `files/generated`.
5. Render templates into `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `memories/MEMORY.md`, and `memories/USER.md`. Keep `home_chat_id: ""` in `config.yaml`; Telegram routing is restricted by `TELEGRAM_ALLOWED_USERS` in `.env`.
6. Verify `config.yaml` contains `memory_enabled: false`, Mnemosyne plugin enabled, and no secrets. Verify `.env` contains `TELEGRAM_ALLOWED_USERS` as comma-separated numeric IDs.
7. Update `/opt/aaas/platform/docker/docker-compose.yaml` structurally under the top-level `services:` mapping. If the file only contains an empty placeholder, replace it with a normal `services:` block plus the tenant service:
   - service/container name: `hermes_{tenant-id}`
   - image: `hermes-tenant:latest`
   - command: `gateway run`
   - mounts tenant folder to `/opt/data` and files folder to `/home/hermes/files`
   - `env_file` points to the tenant `.env`
   - resource limits: `mem_limit: 1g` and `cpus: "1.0"`
8. Start only this tenant: `docker compose up -d hermes_{tenant-id}`.
9. Verify with `docker ps` and `docker logs hermes_{tenant-id} --tail 20`.
10. Seed Mnemosyne with `memories/MEMORY.md` and `memories/USER.md`.
11. Add or update the tenant entry in `/opt/aaas/platform/tenants.yaml`.
12. Send the welcome message through the tenant's Telegram bot to every numeric ID in `TELEGRAM_ALLOWED_USERS`. This only succeeds for users who have already opened the bot and sent `/start`; report any Telegram `403 Forbidden` result as "user must start the bot first":
   `curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="{user-id}" --data-urlencode text="{welcome-message}"`
13. Report tenant ID, container status, Telegram bot link, Mnemosyne seed status, welcome message delivery status per user ID, and registry update status.
