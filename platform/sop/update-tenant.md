# SOP: Update Tenant Configuration

## Purpose
Update a tenant's config, secrets, brand context, owner profile, model, or channels.

## Steps
1. Ask operator for tenant ID.
2. Ask what needs updating: LLM API key, Telegram bot token, brand context, owner profile, model provider/name, or new channel.
3. For secrets, edit `/opt/aaas/tenants/{id}/.env`.
4. For config, edit `/opt/aaas/tenants/{id}/config.yaml`.
5. For brand or owner profile, update memory seed files and re-seed Mnemosyne.
6. For new channels, add token to `.env`, add gateway platform block to `config.yaml`, and update channels in tenants.yaml.
7. Restart only this tenant: `docker compose restart hermes_{tenant-id}`.
8. Verify running: `docker ps | grep hermes_{tenant-id}`.
9. Update tenants.yaml `last_updated`.
10. Confirm update to operator.
