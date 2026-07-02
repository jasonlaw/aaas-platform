# SOP: Write Task Report

## Purpose
Create an operator-readable and AI-readable record after every SOP task and on-demand troubleshooting or fix task, so future improvements can learn from completed work without reprocessing every full report.

## When Required
Run this before declaring any SOP task or operational troubleshooting task complete, including successful, partial, failed, cancelled, or validation-only work.

Use this SOP even when the operator's request did not start from a named SOP, such as "check why tenant X is failing", "inspect this container error", or "fix tenant Y's bot".

**Also run this the moment a bug is found and root-caused, or something worth improving or changing is identified — even if that discovery is incidental to what you were actually asked to do.** Do not wait for task completion, and do not let it depend on whether the current work maps to an SOP step that happens to say "write a report now." If, while onboarding a tenant, answering an operator question, or doing anything else, you find and root-cause a bug, notice a script or SOP behaving wrong, or spot a gap worth changing, write a report for that finding on its own — either immediately, or at the latest by the end of the current task if you judge that safer than context-switching mid-task. A finding does not need to have blocked or been part of the current task to be worth a report; "I was doing X and separately noticed Y" is a normal and expected report to write. When in doubt about whether something rises to this bar, write the report — a report that turns out routine costs little; a root-caused bug that goes unrecorded because it wasn't the day's assigned task is a real loss.

If the finding is low-risk (doc/comment wording, an obvious typo, formatting, a stale example — nothing that can change runtime behavior, decision logic, or output) and outside the protected automation surface in PLATFORM-REFERENCE.md's Rules, it's fine to fix it on the spot rather than defer it — but write the report regardless. The report is what gets a live, one-off fix backported into the versioned source the operator actually maintains; note in the report that the fix was already applied live, and include the exact file and change so the operator can replicate it upstream.

## Trigger Field
Every report's `trigger` field records what caused this task to run. Reports are written by whichever admin-side agent actually did the work — the OpenCode admin agent or the Hermes admin agent. The tenant Hermes agent is never the author, only ever the subject of troubleshooting; it has no access to `platform/reports/` and no path to this SOP.

- `operator` — a human operator started this session interactively (the normal case for onboarding, upgrades, and operator-initiated troubleshooting). Written by the OpenCode admin agent.
- `watchdog` — `aaas-watchdog.sh` invoked OpenCode unattended after automatic restart attempts failed for Agent Vault, a tenant container, or admin Hermes. Set `operator_request` to the watchdog's actual invocation message in this case (do not paraphrase it as if a human typed it) — see `aaas-watchdog.sh`'s `escalate()` function for the exact text, which names the specific entity that failed. Written by the OpenCode admin agent.
- `tenant_request` — a tenant Hermes agent contacted admin Hermes via the API server channel (`support_request`, `operator_alert`, or `llm_key_change`; see `/opt/aaas/platform/skills/handle-tenant-request.md`) and, after investigating, admin Hermes confirmed the issue was valid (platform-side, not a tenant mistake) — whether or not admin Hermes was able to fix it itself. Set `operator_request` to the tenant's message verbatim (do not paraphrase), and set `tenant_id` to the reporting tenant. Written by the Hermes admin agent — this is the one case where Hermes, not OpenCode, is the report's author, since admin Hermes is the agent that actually ran the investigation and has no mechanism to hand the writing off to an OpenCode session. A `support_request` that turns out to be tenant-side (the tenant's own mistake, not a platform issue) does not meet this bar — see `handle-tenant-request.md` for that distinction — and does not require a report.

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
trigger: "operator|watchdog|tenant_request"
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