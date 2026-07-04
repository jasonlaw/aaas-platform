---
name: handle-watchdog-alert
description: >
  Use when woken up by the watchdog after it failed to auto-recover a
  platform entity (admin Hermes, Agent Vault, or a tenant container).
  Covers the full response loop: read the alert, diagnose, attempt recovery,
  write a report, and remove the alert — whether recovery succeeded or not.
  Triggered by a watchdog escalation message of the form
  "{name} is down and automatic restart failed."
---

# Skill: Handle Watchdog Alert

The watchdog already tried to restart the entity several times and failed.
Your job is to go further — diagnose the root cause, attempt a fix if one
is within your authority, write a report, and clean up the alert file
regardless of outcome.

## Step 1 — Read the alert

The watchdog escalation message tells you the exact alert file path, e.g.:

    Your alert file is /opt/aaas/platform/watchdog/admin-hermes-ALERT-20260703-152419.txt

Read that exact file — do not glob for alert files, as a new alert for the
same entity may have been written by a later watchdog cycle while you were
still working. You are responsible for the specific alert file you were given,
not any others.

If for any reason the path was not in your escalation message, list and read
all present alert files and handle them in priority order — Agent Vault first
(priority 0), then admin Hermes, then tenants:

    ls /opt/aaas/platform/watchdog/*-ALERT-*.txt 2>/dev/null

Each alert file tells you:
- Which entity is down (from the filename prefix)
- When the watchdog gave up
- Any extra context the watchdog captured

## Step 2 — Read the incident playbook

Each entity has its own incident playbook under
`/opt/aaas/platform/incidents/`. Follow it for diagnosis and recovery steps.

| Entity | Playbook |
|--------|----------|
| agent-vault | `agent-vault-failure.md` |
| admin-hermes | `hermes-admin-failure.md` |
| hermes_{tenant-id} | `troubleshoot-tenant.md` |

Read the playbook before touching anything. It tells you what to check,
what fixes are safe to apply unattended, and exactly when to stop and
escalate to the operator.

## Step 3 — Diagnose

Run the diagnosis steps from the playbook. Record what you find — exact
commands and their output — because this goes into the report regardless
of whether recovery succeeds.

**Hard constraint if running unattended (--auto, no operator present):**
Never run recreate, stop, or remove on any container for any reason.
Apply only non-recreate fixes. If the only available fix requires a
recreate, stop here and escalate (Step 5).

## Step 4 — Attempt recovery

Work through the playbook's recovery options in order. After each attempt,
re-probe the entity to confirm whether it recovered:

**Admin Hermes:**

    curl -sf http://127.0.0.1:9119/ >/dev/null 2>&1 && echo "OK: dashboard up" || echo "still down"
    cd /opt/aaas/platform/admin && set -a && . ./.env && set +a
    hermes -z "Reply with the single word: PROXY_OK"

**Agent Vault:**

    /opt/aaas/platform/scripts/agent-vault-health.sh

**Tenant container:**

    docker inspect --format '{{.State.Status}}' hermes_{tenant-id}
    docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 5 https://api.telegram.org

If the entity is healthy after a fix, proceed to Step 6 (success path).
If all playbook options are exhausted and the entity is still down,
proceed to Step 5.

## Step 5 — Escalate to operator (NEEDS_HUMAN)

Stop attempting fixes. Send the operator a Telegram message explaining:
- Which entity is down
- What was checked (brief summary)
- What was attempted
- What is blocking automated recovery and what you need from them

    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="${TELEGRAM_HOME_CHANNEL}" \
      --data-urlencode text="⚠️ {name} is down and I could not recover it automatically.
Attempted: {summary of what was tried}.
Blocked on: {what needs operator input}.
See reports/ for the full diagnostic report."

Set report status to `partial` and `needs_human: true` (see Step 7).
Then proceed to Step 7 — the report and alert cleanup still happen even
when recovery failed. Do not leave the alert file in place as a substitute
for the report.

## Step 6 — Verify recovery (success path only)

Run the post-recovery checklist from the playbook. All checks must pass
before writing a success report. If any check fails after what seemed like
a successful fix, go back to Step 4 or escalate per Step 5.

For admin Hermes, also confirm the watchdog itself is still running:

    systemctl status aaas-watchdog.timer
    # Expected: active (waiting)

## Step 7 — Write the report

Write a task report per `/opt/aaas/platform/sop/write-report.md`.

Required fields:
- `trigger: watchdog`
- `operator_request`: the watchdog escalation message verbatim
- `status`: `success` if recovered, `partial` if escalated to operator
- Root Cause Analysis: what caused the failure (even if not fully resolved)
- Actions: every command run and its outcome
- Issues: anything that needs follow-up (persistent config drift,
  missing steps in a SOP, etc.)

Never omit the report because recovery was straightforward — the report
is the audit trail that `analyze-reports.sh` and the operator depend on.
Never omit it because recovery failed either — a `partial` report with
a clear diagnosis is more useful than silence.

## Step 8 — Remove the alert file

Remove the exact alert file you were given in the escalation message,
regardless of whether recovery succeeded or failed. The report is now the
record; the alert file is only a signal to wake you up and should not
persist after you have acted.

    rm -f /opt/aaas/platform/watchdog/{name}-ALERT-{timestamp}.txt

Do not glob and remove all alert files for that entity — a newer alert for
the same entity may have been written by a subsequent watchdog cycle and
belongs to a separate escalation that has not been handled yet.

If you escalated to the operator (Step 5), remove the alert file anyway —
the operator has been notified via Telegram and the report is written. Do
not leave the alert file in place as a second notification mechanism; it
will cause the watchdog to re-escalate on the next cycle even though you
have already handled it.
