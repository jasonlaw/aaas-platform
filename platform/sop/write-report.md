# SOP: Write Task Report

## Purpose
Create an operator-readable and AI-readable record after every SOP task, so future improvements can learn from completed work without reprocessing every full report.

## When Required
Run this before declaring any SOP task complete, including successful, partial, failed, cancelled, or validation-only work.

## Report Locations
- Full report: `/opt/aaas/platform/reports/{sop-name}/{timestamp}_{tenant-or-platform}_{status}.md`
- AI index: `/opt/aaas/platform/reports/INDEX.jsonl`

Use UTC timestamp format `YYYYMMDDTHHMMSSZ`. Use `platform` when the task is not tenant-specific.

## Full Report Format
Write Markdown with this structure:

```markdown
---
report_version: 1
timestamp_utc: "{YYYY-MM-DDTHH:MM:SSZ}"
platform_version: "{contents of /opt/aaas/platform/VERSION}"
sop: "{sop-name}"
status: "success|partial|failed|cancelled|validation-only"
tenant_id: "{tenant-id-or-empty}"
operator_request: "{brief request}"
---

# {SOP Name} Report

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

Example:

```json
{"report_version":1,"timestamp_utc":"2026-06-17T05:30:00Z","platform_version":"0.1.0","sop":"onboard-tenant","status":"partial","tenant_id":"u-moon-cafe","report_path":"/opt/aaas/platform/reports/onboard-tenant/20260617T053000Z_u-moon-cafe_partial.md","summary":"Tenant onboarded; Telegram welcome could not be delivered because users had not started bot.","issues":["Telegram chat not found for two user IDs"],"improvement_signals":["SOP should mention Telegram 400 chat not found"],"next_action":"Owners must open bot and send /start"}
```

## Rules
- Do not put secrets in reports or the index. Redact API keys, bot tokens, access tokens, private URLs, and customer private data.
- For tenant-related fixes, include root cause and fix details in the Markdown report. Keep `INDEX.jsonl` concise: summarize the issue in `issues`, prevention signals in `improvement_signals`, and unresolved follow-up in `next_action`.
- Prefer concise issue and improvement summaries in `INDEX.jsonl`; put details in the Markdown report.
- If updating `INDEX.jsonl` fails, still write the Markdown report and tell the operator the index update failed.
- Before proposing platform improvements, read recent matching index entries first:
  `tail -n 50 /opt/aaas/platform/reports/INDEX.jsonl`
