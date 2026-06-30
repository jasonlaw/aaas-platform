# SOP: Write Task Report

## Purpose
Create an operator-readable and AI-readable record after every SOP task and on-demand troubleshooting or fix task, so future improvements can learn from completed work without reprocessing every full report.

## When Required
Run this before declaring any SOP task or operational troubleshooting task complete, including successful, partial, failed, cancelled, or validation-only work.

Use this SOP even when the operator's request did not start from a named SOP, such as "check why tenant X is failing", "inspect this container error", or "fix tenant Y's bot".

## Trigger Field
Every report's `trigger` field records what caused OpenCode to run this task, not which agent wrote the report — reports are always written by OpenCode itself; Hermes (admin or tenant) is never the author, only ever the subject of troubleshooting.

- `operator` — a human operator started this session interactively (the normal case for onboarding, upgrades, and operator-initiated troubleshooting).
- `watchdog` — `hermes-admin-watchdog.sh` invoked OpenCode unattended after automatic Hermes admin restart attempts failed. Set `operator_request` to the watchdog's actual invocation message in this case (do not paraphrase it as if a human typed it) — see `hermes-admin-watchdog.sh`'s `--message` argument for the exact text.

If a task is unsure which value applies (rare — this should only happen for new automation, not regular operator sessions), default to `operator` rather than leaving the field blank; an unset `trigger` is harder to distinguish from a missed report than a possibly-wrong-but-present value.

## Report Locations
- Full report: `/opt/aaas/platform/reports/{timestamp}_{sop-or-task-name}_{tenant-or-platform}_{status}.md`
- AI index: `/opt/aaas/platform/reports/INDEX.jsonl`

Use UTC timestamp format `YYYYMMDDTHHMMSSZ`. Use `platform` when the task is not tenant-specific. For on-demand troubleshooting that does not map cleanly to another SOP, use `troubleshoot-tenant` or `troubleshoot-platform` as the task name. Write full reports directly under /opt/aaas/platform/reports/; do not create category, SOP, tenant, or status subfolders because the filename already contains the SOP/task name, tenant/platform target, and status.

## Full Report Format
Write Markdown with this structure:

```markdown
---
report_version: 1
timestamp_utc: "{YYYY-MM-DDTHH:MM:SSZ}"
platform_version: "{contents of /opt/aaas/platform/VERSION}"
sop: "{sop-or-task-name}"
status: "success|partial|failed|cancelled|validation-only"
tenant_id: "{tenant-id-or-empty}"
trigger: "operator|watchdog"
operator_request: "{brief request}"
---

# {SOP Or Task Name} Report

## Summary
One short paragraph describing the outcome.

## Inputs
- Operator request:
- Tenant ID:
- Sources used:

## Actions
- Commands run:
- Files created or changed:
- Containers/images touched:

## Validation
- Checks performed:
- Results:

## Root Cause Analysis
- Required when a tenant-related issue was identified and fixed.
- Root cause:
- Evidence and analysis:
- Fix applied:
- Why this fix addresses the cause:
- Prevention or follow-up:

## Issues
- Errors:
- Workarounds:
- User action needed:

## Improvement Signals
- What was confusing:
- Missing SOP/script coverage:
- Suggested platform changes:

## Final State
- Status:
- Follow-up:
```

## AI Index Format
Append exactly one compact JSON object as one line to `/opt/aaas/platform/reports/INDEX.jsonl`.

Required keys:
- `report_version`
- `timestamp_utc`
- `platform_version`
- `sop`
- `status`
- `tenant_id`
- `trigger`
- `report_path`
- `summary`
- `issues`
- `improvement_signals`
- `next_action`

Recommended keys for tenant harness work:
- `tenant_harness_version`
- `verification_profile`
- `harness_summary`
- `eval_summary`
- `failure_type`
- `root_cause_code`
- `commands_failed`
- `commands_succeeded`

Example:

```json
{"report_version":1,"timestamp_utc":"2026-06-17T05:30:00Z","platform_version":"0.1.0","sop":"onboard-tenant","status":"partial","tenant_id":"u-moon-cafe","trigger":"operator","report_path":"/opt/aaas/platform/reports/20260617T053000Z_onboard-tenant_u-moon-cafe_partial.md","summary":"Tenant onboarded; Telegram welcome could not be delivered because users had not started bot.","issues":["Telegram chat not found for two user IDs"],"improvement_signals":["SOP should mention Telegram 400 chat not found"],"next_action":"Owners must open bot and send /start"}
```

## Rules
- Do not put secrets in reports or the index. Redact API keys, bot tokens, access tokens, private URLs, and customer private data.
- For tenant-related fixes, include root cause and fix details in the Markdown report. Keep `INDEX.jsonl` concise: summarize the issue in `issues`, prevention signals in `improvement_signals`, and unresolved follow-up in `next_action`.
- For tenant operations, include the tenant harness check output summary and any tenant eval results. If checks were skipped, explain why and state the tenant-facing risk.
- Prefer concise issue and improvement summaries in `INDEX.jsonl`; put details in the Markdown report.
- If updating `INDEX.jsonl` fails, still write the Markdown report and tell the operator the index update failed.
- Before proposing platform improvements, read recent matching index entries first:
  `tail -n 50 /opt/aaas/platform/reports/INDEX.jsonl`
- For broader platform improvement work, prefer `/opt/aaas/platform/scripts/analyze-reports.sh` when available.
- If this report records a tenant root cause, an incident, or a recurring SOP friction point worth remembering past this single report, follow `/opt/aaas/platform/sop/sync-knowledge-vault.md` to write or update a vault note after writing the report. Skip this for routine, no-news reports - the vault is for durable knowledge, not a mirror of every report. A failed or skipped vault sync never blocks report completion.