# SOP: Improve SOP

## Purpose
Turn task reports, repeated operator friction, and validation failures into safer SOP improvements without editing upgrade-managed native SOP files directly.

## When Required
Use this SOP when the operator asks to improve, review, tune, or harden an SOP, or when recent reports show repeated confusion, missing coverage, or recurring manual fixes.

Do not use this SOP as a shortcut during an active tenant or platform operation. Finish the operational task first, write its task report with `/opt/aaas/platform/sop/write-report.md`, then run this SOP as a separate improvement task.

## Upgrade Safety Rule
Treat `/opt/aaas/platform/sop/` as native, upgrade-managed content.

Do not edit native SOP files in place unless the operator explicitly asks to patch the platform source. Instead, write proposed improvements to:

- Improvement proposals: `/opt/aaas/platform/reports/sop-improvements/{timestamp}_{sop-name}.md`

There is no mechanism for an SOP change to take effect before it is reviewed and merged into the native file — every improvement, however urgent, goes through a proposal. If the operator wants a change to apply immediately, patch the native SOP directly with their explicit confirmation and record that as the reviewed change; do not invent a parallel "active locally" state for an SOP.

## Inputs
Collect or infer:

- SOP name or operational area to improve.
- Operator request and desired outcome.
- Recent matching reports from `/opt/aaas/platform/reports/INDEX.jsonl`.
- Current native SOP text from `/opt/aaas/platform/sop/{sop-name}.md`.
- Any related scripts, checklists, harnesses, incident playbooks, or templates.

## Steps
1. Identify the target SOP or operational area. If the request is broad, start with the SOP named most often in recent report improvement signals.
2. Read the current native SOP. Treat it as the baseline, not as an editable target.
3. Read recent report signals:
   - Prefer `/opt/aaas/platform/scripts/analyze-reports.sh` when available.
   - Otherwise inspect the latest relevant entries:
     `tail -n 100 /opt/aaas/platform/reports/INDEX.jsonl`
4. Group findings into:
   - Repeated failures or near misses.
   - Missing pre-flight checks.
   - Ambiguous operator questions.
   - Validation gaps.
   - Steps that should move into scripts or checklists.
   - Documentation-only clarifications.
5. Check related automation before proposing SOP text. If a script, checklist, harness, or template already enforces the behavior, reference it instead of duplicating too much logic in the SOP.
6. Draft the improvement as a proposal document.
7. Preserve native SOP intent and ordering where possible. Keep changes narrow, operational, and testable.
8. Include an "Upgrade Notes" section in every proposal describing:
   - Native SOP version or platform version reviewed.
   - Files intentionally not modified.
9. Validate the proposed SOP by walking through one realistic scenario from recent reports. Confirm that the new wording would have changed the outcome or reduced ambiguity.
10. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `improve-sop`.

## Proposal Format
Use this structure for `/opt/aaas/platform/reports/sop-improvements/{timestamp}_{sop-name}.md`:

```markdown
---
proposal_version: 1
target_sop: "{sop-name}"
platform_version: "{contents of /opt/aaas/platform/VERSION}"
created_utc: "{YYYY-MM-DDTHH:MM:SSZ}"
status: "proposed"
---

# SOP Improvement Proposal: {SOP Name}

## Summary
One short paragraph describing the proposed change.

## Evidence
- Reports reviewed:
- Repeated signals:
- Operator request:

## Proposed Changes
- Change:
- Reason:
- Risk:

## Suggested Patch
Provide concise replacement or insertion text for the native SOP file.

## Validation
- Scenario:
- Why the change helps:

## Upgrade Notes
- Native files not modified:
```

## Rules
- Do not put secrets in SOP proposals, reports, or index entries.
- Do not weaken safety gates, confirmation steps, tenant isolation, or validation requirements to make an SOP shorter.
- Prefer executable checks in scripts or checklists when the same instruction would otherwise be repeated across SOPs.
- If the operator wants a proposal applied now, patch the native SOP file directly with their explicit confirmation rather than writing it anywhere else — do not defer an approved change into an unreviewed parallel file.
- Report clearly whether the improvement is still a proposal awaiting review or has already been merged into the native SOP.
