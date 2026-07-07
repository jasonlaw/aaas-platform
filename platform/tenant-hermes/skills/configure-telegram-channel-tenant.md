---
name: configure-telegram-channel-tenant
description: >
  Rewrite a live tenant's Telegram credentials (bot token, allow list, home
  channel) via `docker exec {container} hermes config set`. Use ONLY for
  reconfiguring an already-onboarded, already-running tenant — e.g.
  rotating a bot token, changing the allow list, or changing the home
  channel. Does NOT cover a tenant's first-ever .env write during
  onboarding — that's a plain file write in sop/onboard-tenant.md step 5,
  since the container doesn't exist yet at that point. For the admin
  equivalent, see skills/configure-telegram-channel-admin.md.
---

# Skill: Configure Telegram Channel (Tenant)

## Rule

Always write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, and
`TELEGRAM_HOME_CHANNEL` via `docker exec {container} hermes config set`.
Never use `sed` or a manual file edit on a running tenant.

`hermes config set` decides for itself whether a key lands in `.env` or
`config.yaml` — secrets go to `.env`, everything else to `config.yaml`.
`TELEGRAM_BOT_TOKEN` lands in `.env`. `TELEGRAM_ALLOWED_USERS` and
`TELEGRAM_HOME_CHANNEL` may land in either file. Both outcomes are
correct. Never move or copy a value between files after it's written —
`hermes config get` reads it back correctly regardless of which file
backs it.

## Preconditions

- The tenant's container is already running — `docker ps` shows
  `hermes_{tenant-id}` (or whatever this tenant's compose service is
  named) as `Up`. If not, troubleshoot first (see
  sop/troubleshoot-tenant.md) rather than using this skill.
- You have, from the caller (operator or the tenant's own self-service
  request via handle-tenant-request.md): the new Telegram bot token
  and/or allow list and/or home channel. This skill only writes what
  it's given.

## Inputs

| Name | Meaning |
|---|---|
| `CONTAINER` | The tenant's container name, e.g. `hermes_{tenant-id}` |
| `BOT_TOKEN` | New Telegram bot token from @BotFather (omit if not rotating the token) |
| `ALLOWED_USERS` | New comma-separated numeric Telegram user IDs, no spaces (omit if not rotating the allow list) |
| `HOME_CHANNEL` | New single numeric ID, the primary contact for Hermes-initiated messages (omit if not changing it) |

`HOME_CHANNEL` accepts exactly one ID, never a list.

## Step 1 — Sanity-check inputs before writing anything

- If `BOT_TOKEN` is provided, it must look like `{numeric}:{35-ish char
  body}` (colon-separated, numeric prefix). Reject anything else.
- If `ALLOWED_USERS` is provided, it must be non-empty and every entry
  numeric. Do not let the allow list go empty.
- If `HOME_CHANNEL` is provided, it must be a single numeric ID (not a
  list), and it must already be present in the tenant's current
  `TELEGRAM_ALLOWED_USERS` (or in the new `ALLOWED_USERS`, if both are
  being changed together).
- At least one of `BOT_TOKEN` / `ALLOWED_USERS` / `HOME_CHANNEL` must be
  provided.

## Step 2 — Write via `docker exec ... hermes config set`

    if [ -n "${BOT_TOKEN:-}" ]; then
      docker exec "$CONTAINER" hermes config set TELEGRAM_BOT_TOKEN "$BOT_TOKEN"
    fi
    if [ -n "${ALLOWED_USERS:-}" ]; then
      docker exec "$CONTAINER" hermes config set TELEGRAM_ALLOWED_USERS "$ALLOWED_USERS"
    fi
    if [ -n "${HOME_CHANNEL:-}" ]; then
      docker exec "$CONTAINER" hermes config set TELEGRAM_HOME_CHANNEL "$HOME_CHANNEL"
    fi

This lands on the bind-mounted `.env`, so it survives
`docker compose up --force-recreate`. The running gateway process does
not pick it up on its own — restart it:

    docker compose restart {tenant-service-name}

## Step 3 — Verify

`hermes config set` doesn't print the value back, and secrets are never
printed anyway — verify presence, not content:

    if [ -n "${BOT_TOKEN:-}" ]; then
      docker exec "$CONTAINER" hermes config get TELEGRAM_BOT_TOKEN >/dev/null \
        && echo "OK: bot token set" || echo "FAIL: bot token not set"
    fi
    if [ -n "${ALLOWED_USERS:-}" ]; then
      WRITTEN_USERS=$(docker exec "$CONTAINER" hermes config get TELEGRAM_ALLOWED_USERS)
      [ "$WRITTEN_USERS" = "$ALLOWED_USERS" ] \
        && echo "OK: allow list matches" \
        || echo "FAIL: allow list mismatch — written='${WRITTEN_USERS}' expected='${ALLOWED_USERS}'"
    fi
    if [ -n "${HOME_CHANNEL:-}" ]; then
      WRITTEN_HOME=$(docker exec "$CONTAINER" hermes config get TELEGRAM_HOME_CHANNEL)
      [ "$WRITTEN_HOME" = "$HOME_CHANNEL" ] \
        && echo "OK: home channel matches" \
        || echo "FAIL: home channel mismatch — written='${WRITTEN_HOME}' expected='${HOME_CHANNEL}'"
    fi

If `hermes config get` errors with "unknown key" or similar, the
tenant's image predates the Hermes version this key needs — stop and
escalate. Do not fall back to hand-editing `.env`.

## Step 4 — Test message (after the restart in Step 2)

Send a test message. Use `${HOME_CHANNEL}` if this call set it;
otherwise any ID currently in the allow list:

    curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="${HOME_CHANNEL:-one-allowed-id}" \
      --data-urlencode text="Telegram channel reconfigured and live."

A `400 Bad Request: chat not found` or `403 Forbidden` means that user
hasn't sent `/start` to the bot yet — report it, don't treat it as a
failure.

## Never

- Never write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, or
  `TELEGRAM_HOME_CHANNEL` with `sed` or a manual file edit on a running
  tenant — always go through `docker exec ... hermes config set`.
- Never move or duplicate a value between `.env` and `config.yaml` after
  `hermes config set` writes it.
- Never write a `TELEGRAM_HOME_CHANNEL` that isn't in the tenant's allow
  list, and never write more than one ID to it.
- Never run this skill against a tenant whose container isn't running —
  that's onboarding's job (sop/onboard-tenant.md step 5).
- Never print the bot token in a task report, log, or verification output.
- Never forget the restart in Step 2 — the write lands on disk
  immediately but the running gateway process keeps its already-loaded
  values until restarted.
