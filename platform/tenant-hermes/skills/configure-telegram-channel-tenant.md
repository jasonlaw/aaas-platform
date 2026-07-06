---
name: configure-telegram-channel-tenant
description: >
  Rewrite a live tenant's Telegram credentials (bot token, allow list, home
  channel) via `docker exec {container} hermes config set` instead of
  hand-editing the tenant's .env. Use this ONLY for reconfiguring an
  already-onboarded, already-running tenant — e.g. rotating a compromised
  bot token, changing who's on the allow list, or changing the primary
  contact for alerts. Does NOT cover a tenant's first-ever .env write during
  onboarding: at that point the container doesn't exist yet, so there's no
  `hermes` process to call — that initial write is a plain file write done
  in sop/onboard-tenant.md step 5. For the admin equivalent, see
  skills/configure-telegram-channel-admin.md — admin Hermes is host-installed
  and reachable directly, unlike tenants.
---

# Skill: Configure Telegram Channel (Tenant)

## Why this exists

Tenant onboarding renders `TELEGRAM_BOT_TOKEN` and `TELEGRAM_ALLOWED_USERS`
directly into `.env` by template substitution, because at that point the
tenant container hasn't been created yet (`add-tenant-compose-service.sh`
requires `.env` to already exist first) and there is no `hermes` binary on
the host to call for a tenant — `hermes`/`gateway` only ever live inside
the container image at `/opt/hermes/.venv` (root-owned, read-only — see
`platform/docker/Dockerfile`).

Once a tenant's container is up, though, that same `hermes` binary is
reachable via `docker exec`, and using the official `hermes config set`
for any *later* change (token rotation, allow-list edits) is safer than
hand-editing the bind-mounted `.env` with `sed`: it resolves the right
file and line regardless of the file's current state.

## Preconditions

- The tenant's container is already running — `docker ps` shows
  `hermes_{tenant-id}` (or whatever this tenant's compose service is
  named) as `Up`. If it's not running, this skill doesn't apply; that
  means either onboarding hasn't finished yet, or the container is down
  for another reason — troubleshoot that first (see
  sop/troubleshoot-tenant.md), don't try to reconfigure a dead container.
- You have, from the caller (operator or the tenant's own self-service
  request via handle-tenant-request.md): the new Telegram bot token and/or
  allow list. This skill only writes what it's given.

## Inputs

| Name | Meaning |
|---|---|
| `CONTAINER` | The tenant's container name, e.g. `hermes_{tenant-id}` |
| `BOT_TOKEN` | New Telegram bot token from @BotFather (omit if not rotating the token) |
| `ALLOWED_USERS` | New comma-separated numeric Telegram user IDs, no spaces (omit if not rotating the allow list) |
| `HOME_CHANNEL` | New single numeric ID, the primary contact for Hermes-initiated messages (omit if not changing it) |

`HOME_CHANNEL` accepts exactly one ID, never a list — same convention as
admin Hermes (see `skills/setup-admin-hermes.md` Step 3.1).

## Step 1 — Sanity-check inputs before writing anything

Do not call `hermes config set` with an empty or malformed value — it will
happily write it.

- If `BOT_TOKEN` is provided, it must look like `{numeric}:{35-ish char
  body}` (colon-separated, numeric prefix). Reject anything else.
- If `ALLOWED_USERS` is provided, it must be non-empty and every entry
  numeric. Do not let this tenant's allow list go empty — an enabled
  Telegram channel with no allowed users is not a valid state.
- If `HOME_CHANNEL` is provided, it must be a single numeric ID (not a
  list), and it must already be present in the tenant's current
  `TELEGRAM_ALLOWED_USERS` (or in the new `ALLOWED_USERS`, if both are
  being changed together) — a home channel that isn't an allowed user is
  not a valid state.
- At least one of `BOT_TOKEN` / `ALLOWED_USERS` / `HOME_CHANNEL` must be
  provided — don't call this skill with nothing to write.

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

`hermes config set`'s routing rule is **secrets go to `.env`, everything
else goes to `config.yaml`** — not whether the key name looks env-var-
shaped. `TELEGRAM_BOT_TOKEN` is a credential and lands in `.env`;
`TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL` are access/behavior
settings and may legitimately land in either file depending on this
Hermes version's own classification. **Either destination is correct** —
never move a value once written, that reintroduces exactly the drift this
skill exists to remove.

This lands on the bind-mounted `.env`, so it survives a
`docker compose up --force-recreate`. It does not, however, get picked up
by the already-running gateway process on its own — restart it:

    docker compose restart {tenant-service-name}

## Step 3 — Verify

`hermes config set` doesn't print the value back by default, and this repo's
policy is to never print secrets anyway, so verify presence, not content:

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

If `hermes config get` errors with "unknown key" or similar, treat that as
a signal this tenant's image predates the Hermes version this key needs —
stop and escalate rather than falling back to hand-editing `.env`, which
would silently reintroduce the inconsistency this skill exists to remove.

## Step 4 — Test message (after the restart in Step 2)

Send a test message to confirm delivery, to any ID now in the allow list:

    curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="{one-allowed-id}" \
      --data-urlencode text="Telegram channel reconfigured and live."

A `400 Bad Request: chat not found` or `403 Forbidden` means that user
hasn't opened the bot and sent `/start` yet — expected for a not-yet-active
user, not a failure of this skill. Report it as such rather than treating
it as blocking.

## Never

- Never write `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, or
  `TELEGRAM_HOME_CHANNEL` with `sed` or a manual file edit on a running
  tenant — always go through `docker exec ... hermes config set`.
- Never move or duplicate a value between `.env` and `config.yaml` after
  `hermes config set` writes it. Whichever file it lands in reflects
  Hermes's own secret/non-secret classification for that key — moving it
  yourself creates two sources of truth instead of one.
- Never write a `TELEGRAM_HOME_CHANNEL` that isn't in the tenant's allow
  list, and never write more than one ID to it — it accepts exactly one
  primary contact.
- Never run this skill against a tenant whose container isn't running yet
  — that's onboarding's job (sop/onboard-tenant.md step 5), which uses a
  plain file write instead because no `hermes` process exists to call.
- Never print the bot token in a task report, log, or verification output.
- Never forget the restart in Step 2 — the write lands on disk immediately
  but the running gateway process keeps using its already-loaded values
  until restarted.
