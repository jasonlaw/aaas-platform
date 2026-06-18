# SOP: Write Task Report

## Purpose
Create an operator-readable and AI-readable record after every SOP task and on-demand troubleshooting or fix task, so future improvements can learn from completed work without reprocessing every full report.

## When Required
Run this before declaring any SOP task or operational troubleshooting task complete, including successful, partial, failed, cancelled, or validation-only work.

Use this SOP even when the operator's request did not start from a named SOP, such as "check why tenant X is failing", "inspect this container error", or "fix tenant Y's bot".

## Report Locations
- Full report: `/opt/aaas/platform/reports/{sop-or-task-name}/{timestamp}_{tenant-or-platform}_{status}.md`
- AI index: `/opt/aaas/platform/reports/INDEX.jsonl`

Use UTC timestamp format `YYYYMMDDTHHMMSSZ`. Use `platform` when the task is not tenant-specific. For on-demand troubleshooting that does not map cleanly to another SOP, use `troubleshoot-tenant` or `troubleshoot-platform` as the task name.

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
{"report_version":1,"timestamp_utc":"2026-06-17T05:30:00Z","platform_version":"0.1.0","sop":"onboard-tenant","status":"partial","tenant_id":"u-moon-cafe","report_path":"/opt/aaas/platform/reports/onboard-tenant/20260617T053000Z_u-moon-cafe_partial.md","summary":"Tenant onboarded; Telegram welcome could not be delivered because users had not started bot.","issues":["Telegram chat not found for two user IDs"],"improvement_signals":["SOP should mention Telegram 400 chat not found"],"next_action":"Owners must open bot and send /start"}
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
