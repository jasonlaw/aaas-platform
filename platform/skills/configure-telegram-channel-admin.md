---
name: configure-telegram-channel-admin
description: >
  Write admin Hermes's Telegram credentials (bot token, allow list, home
  channel) into /opt/aaas/platform/admin/.env using the official
  `hermes config set` CLI. Called by setup-admin-hermes.md Step 3.1.
  Admin-only — admin Hermes is host-installed, so `hermes` is directly
  reachable on PATH. For the tenant equivalent, see
  tenant-hermes/skills/configure-telegram-channel-tenant.md, which uses
  `docker exec` instead.
---

# Skill: Configure Telegram Channel (Admin)

## Rule

Always write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, and
`TELEGRAM_HOME_CHANNEL` via `hermes config set`. Never use `sed`,
template substitution, or a manual file edit for these three keys.

`hermes config set` decides for itself whether a key lands in `.env` or
`config.yaml` — secrets go to `.env`, everything else to `config.yaml`.
`TELEGRAM_BOT_TOKEN` lands in `.env`. `TELEGRAM_ALLOWED_USERS` and
`TELEGRAM_HOME_CHANNEL` may land in either file. Both outcomes are
correct. Never move or copy a value between files after it's written —
`hermes config get` reads it back correctly regardless of which file
backs it.

## Preconditions

- Admin Hermes is installed on the host (setup-admin-hermes.md Step 1),
  so `hermes` is on PATH directly — no `docker exec` involved.
- `/opt/aaas/platform/admin` already exists with a rendered `.env` and
  `config.yaml` (setup-admin-hermes.md Step 2).
- You have, from the caller: the Telegram bot token, the allow list
  (comma-separated numeric IDs), and which allowed ID is the home channel
  (setup-admin-hermes.md's Ask The Operator item 7) — this skill only
  writes what it's given.

## Inputs

| Name | Meaning |
|---|---|
| `BOT_TOKEN` | Telegram bot token from @BotFather |
| `ALLOWED_USERS` | Comma-separated numeric Telegram user IDs, no spaces |
| `HOME_CHANNEL` | One numeric ID, must be a member of `ALLOWED_USERS` — mandatory for admin |

## Step 1 — Sanity-check inputs before writing anything

- `BOT_TOKEN` must look like `{numeric}:{35-ish char body}` (colon-separated,
  numeric prefix). Reject anything else rather than writing it.
- `ALLOWED_USERS` must be non-empty and every entry numeric. Do not
  proceed with an empty list — go back to the caller and ask again.
- `HOME_CHANNEL` must be one of the IDs already in `ALLOWED_USERS`. If the
  caller only gave one allowed ID, use it automatically with no separate
  confirmation.

## Step 2 — Write via `hermes config set`

    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_BOT_TOKEN "$BOT_TOKEN"
    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_ALLOWED_USERS "$ALLOWED_USERS"
    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_HOME_CHANNEL "$HOME_CHANNEL"

Safe to re-run (e.g. rotating the bot token later) regardless of whether
`.env` currently has these keys absent, commented out, or set.

## Step 3 — Verify

`hermes config set` doesn't print the value back, and secrets are never
printed anyway — verify presence, not content:

    HERMES_HOME=/opt/aaas/platform/admin hermes config get TELEGRAM_BOT_TOKEN >/dev/null \
      && echo "OK: bot token set" || echo "FAIL: bot token not set"
    WRITTEN_USERS=$(HERMES_HOME=/opt/aaas/platform/admin hermes config get TELEGRAM_ALLOWED_USERS)
    [ "$WRITTEN_USERS" = "$ALLOWED_USERS" ] \
      && echo "OK: allow list matches" \
      || echo "FAIL: allow list mismatch — written='${WRITTEN_USERS}' expected='${ALLOWED_USERS}'"
    WRITTEN_HOME=$(HERMES_HOME=/opt/aaas/platform/admin hermes config get TELEGRAM_HOME_CHANNEL)
    [ "$WRITTEN_HOME" = "$HOME_CHANNEL" ] \
      && echo "OK: home channel matches" \
      || echo "FAIL: home channel mismatch — written='${WRITTEN_HOME}' expected='${HOME_CHANNEL}'"

If `hermes config get` errors with "unknown key" or similar, the
installed Hermes version predates `TELEGRAM_HOME_CHANNEL` (added in
0.13.1) — stop and escalate. Do not fall back to hand-editing `.env`.

Do not inspect, edit, or "clean up" `config.yaml`'s Telegram block as
part of this verification. `hermes config get` is the only check needed,
regardless of which file backs a given key.

## Step 4 — Test message (only after admin Hermes's gateway is running)

Requires setup-admin-hermes.md Step 7 to have started the gateway
service. Send a test message to `HOME_CHANNEL`:

    curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="${HOME_CHANNEL}" \
      --data-urlencode text="Admin Hermes Telegram channel is live."

A `400 Bad Request: chat not found` or `403 Forbidden` means that user
hasn't sent `/start` to the bot yet — report it, don't treat it as a
failure.

## Never

- Never write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, or
  `TELEGRAM_HOME_CHANNEL` with `sed`, template substitution, or a manual
  file edit — always go through `hermes config set`.
- Never move, copy, or duplicate a value between `.env` and `config.yaml`
  after `hermes config set` writes it.
- Never print the bot token in a task report, log, or verification output.
- Never call this skill without `HERMES_HOME=/opt/aaas/platform/admin` set
  explicitly per-invocation — an unset `HERMES_HOME` silently targets
  `~/.hermes`'s default profile instead of the admin profile.
