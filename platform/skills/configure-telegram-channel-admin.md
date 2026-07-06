---
name: configure-telegram-channel-admin
description: >
  Write admin Hermes's Telegram credentials (bot token, allow list, home
  channel) into /opt/aaas/platform/admin/.env using the official
  `hermes config set` CLI instead of hand-editing .env with sed. Called by
  setup-admin-hermes.md Step 3.1. Admin-only — admin Hermes is
  host-installed, so `hermes` is directly reachable on PATH. For the
  equivalent tenant operation, see
  tenant-hermes/skills/configure-telegram-channel-tenant.md instead; the
  two are separate skills because tenants only have a `hermes` binary
  once their container is running, so tenant writes always go through
  `docker exec` while admin's don't.
---

# Skill: Configure Telegram Channel (Admin)

## Why this exists

Admin setup used to fill in Telegram values with `sed -i` against
commented-out placeholder lines in `.env`. That's correct only as long as
the line's exact shape (comment prefix, placeholder text) never drifts,
which is fragile and has already been a source of inconsistency.

`hermes` ships an official command for exactly this — `hermes config set
<KEY> <VALUE>` — which resolves whether a key belongs in `.env` or
`config.yaml` and writes it correctly regardless of the file's current
state (key absent, present, or commented out).

`hermes config set`'s routing rule is **secrets go to `.env`, everything
else goes to `config.yaml`** — it is not based on whether the key name
looks env-var-shaped. In practice this means `TELEGRAM_BOT_TOKEN` (a
credential) lands in `.env`, while `TELEGRAM_ALLOWED_USERS` and
`TELEGRAM_HOME_CHANNEL` (access/behavior settings, not secrets) may
legitimately land in `config.yaml`. **This is correct behavior, not a
misfire** — do not "fix" it by moving the value to `.env` by hand. Doing
so reintroduces exactly the hand-editing drift this skill exists to
remove, and is explicitly forbidden below.

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
| `HOME_CHANNEL` | One numeric ID, must be a member of `ALLOWED_USERS` — mandatory for admin, since admin Hermes always enables Telegram with a home channel once enabled at all (setup-admin-hermes.md Ask The Operator item 7); the tenant skill treats it as optional per-call since a rotation may not touch it |

## Step 1 — Sanity-check inputs before writing anything

Do not call `hermes config set` with an empty or malformed value — it will
happily write it.

- `BOT_TOKEN` must look like `{numeric}:{35-ish char body}` (colon-separated,
  numeric prefix). Reject anything else rather than writing it.
- `ALLOWED_USERS` must be non-empty and every entry numeric. An enabled
  Telegram channel with no allowed users is not a valid state — do not
  proceed with an empty list; go back to the caller and ask again.
- `HOME_CHANNEL` must be one of the IDs already in `ALLOWED_USERS`. If the
  caller only gave one allowed ID, use it automatically with no separate
  confirmation.

## Step 2 — Write via `hermes config set`

    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_BOT_TOKEN "$BOT_TOKEN"
    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_ALLOWED_USERS "$ALLOWED_USERS"
    HERMES_HOME=/opt/aaas/platform/admin hermes config set TELEGRAM_HOME_CHANNEL "$HOME_CHANNEL"

All three are written the same way, via `hermes config set` — but do not
assume they all land in the same file. `TELEGRAM_BOT_TOKEN` is a secret
and lands in `.env`; `TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL`
may land in either `.env` or `config.yaml` depending on this Hermes
version's own secret/non-secret classification. Never write these three
values with `sed`, a template render, or by hand, and never relocate a
value from wherever `hermes config set` put it to somewhere else —
`hermes config get` is how you read it back regardless of which file it's
actually in, so there is never a need to know or care.

This works whether `.env` currently has the keys absent, commented out, or
already set to an old value — `hermes config set` finds or creates the
right line every time, so it is safe to re-run (e.g. rotating the admin
bot token later) without first checking what state the file is in.

## Step 3 — Verify

`hermes config set` doesn't print the value back by default, and this repo's
policy is to never print secrets anyway, so verify presence, not content:

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

If `hermes config get` errors with "unknown key" or similar instead of
printing a value or a clean empty result, treat that as a signal the
installed Hermes version doesn't recognize one of these three keys (e.g.
a host running a pre-0.13.1 Hermes, before `TELEGRAM_HOME_CHANNEL`
existed — see `admin-hermes/env.template`'s note on this) — stop and
escalate rather than falling back to hand-editing `.env` for just that
one key, which would silently reintroduce the inconsistency this skill
exists to remove.

Do not inspect or edit `config.yaml`'s Telegram block as part of this
verification, and do not "clean up" or move any value you find there.
Whichever file(s) `hermes config set` used — `.env`, `config.yaml`, or
both — are correct by definition; `hermes config get` above is the only
verification needed, and it works regardless of which file backs a given
key. The `home_chat_id` field in the template may be inert legacy
scaffolding, or it may be exactly where this Hermes version now persists
`TELEGRAM_HOME_CHANNEL` — either way, treat it as Hermes's internal
storage detail, not something this skill reads or writes directly.

## Step 4 — Test message (only after admin Hermes's gateway is running)

This can't be verified until setup-admin-hermes.md Step 7 has started the
gateway service. Send a test message to `HOME_CHANNEL`:

    curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="${HOME_CHANNEL}" \
      --data-urlencode text="Admin Hermes Telegram channel is live."

A `400 Bad Request: chat not found` or `403 Forbidden` means that user
hasn't opened the bot and sent `/start` yet — expected for a not-yet-active
user, not a failure of this skill. Report it as such rather than treating
it as blocking.

## Never

- Never write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, or
  `TELEGRAM_HOME_CHANNEL` with `sed`, template substitution, or a manual
  file edit — always go through `hermes config set`.
- Never move, copy, or duplicate a value between `.env` and `config.yaml`
  after `hermes config set` writes it, even if it landed somewhere you
  didn't expect. `hermes config set`'s file choice reflects its own
  secret/non-secret classification for that key — moving the value
  yourself doesn't correct anything, it just creates two sources of truth
  and reintroduces the drift risk this skill exists to remove.
- Never print the bot token in a task report, log, or verification output.
- Never call this skill without `HERMES_HOME=/opt/aaas/platform/admin` set
  explicitly per-invocation — an unset `HERMES_HOME` silently targets
  `~/.hermes`'s default profile instead of the admin profile.
