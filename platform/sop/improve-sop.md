# SOP: Improve SOP

## Purpose
Turn task reports, repeated operator friction, and validation failures into safer SOP improvements without editing upgrade-managed native SOP files directly.

## When Required
Use this SOP when the operator asks to improve, review, tune, or harden an SOP, or when recent reports show repeated confusion, missing coverage, or recurring manual fixes.

Do not use this SOP as a shortcut during an active tenant or platform operation. Finish the operational task first, write its task report with `/opt/aaas/platform/sop/write-report.md`, then run this SOP as a separate improvement task.

## Upgrade Safety Rule
Treat `/opt/aaas/platform/sop/` as native, upgrade-managed content.

Do not edit native SOP files in place unless the operator explicitly asks to patch the platform source. Instead, write proposed or local improvements to one of these locations:

- Local active overrides: `/opt/aaas/platform/local/sop/{sop-name}.md`
- Improvement proposals: `/opt/aaas/platform/reports/sop-improvements/{timestamp}_{sop-name}.md`

If `/opt/aaas/platform/local/sop/` does not exist, create it before writing an active local override. If the platform does not yet load local overrides automatically, write a proposal instead and report that activation needs a platform loader change.

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
6. Draft the improvement as either:
   - A full local override, when the operator wants the agent to use it immediately.
   - A proposal document, when the change needs review or loader support.
7. Preserve native SOP intent and ordering where possible. Keep changes narrow, operational, and testable.
8. Include an "Upgrade Notes" section in every override or proposal describing:
   - Native SOP version or platform version reviewed.
   - Files intentionally not modified.
   - How to rebase or retire the override after a platform upgrade.
9. Validate the proposed SOP by walking through one realistic scenario from recent reports. Confirm that the new wording would have changed the outcome or reduced ambiguity.
10. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `improve-sop`.

## Local Override Format
Use this structure for `/opt/aaas/platform/local/sop/{sop-name}.md`:

```markdown
---
override_version: 1
target_native_sop: "{sop-name}"
reviewed_platform_version: "{contents of /opt/aaas/platform/VERSION}"
created_utc: "{YYYY-MM-DDTHH:MM:SSZ}"
status: "active"
---

# Local Override: {SOP Name}

## Why This Override Exists
Short explanation linked to report signals or operator request.

## Native SOP Relationship
- Native file reviewed:
- Native file intentionally not modified:
- Rebase guidance:

## Override Instructions
Write the complete instructions the agent should follow locally.

## Validation
- Scenario tested:
- Expected improvement:
```

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

## Suggested Patch Or Override
Provide concise replacement or insertion text.

## Validation
- Scenario:
- Why the change helps:

## Upgrade Notes
- Native files not modified:
- Rebase guidance:
```

## Rules
- Do not put secrets in SOP overrides, proposals, reports, or index entries.
- Do not weaken safety gates, confirmation steps, tenant isolation, or validation requirements to make an SOP shorter.
- Prefer executable checks in scripts or checklists when the same instruction would otherwise be repeated across SOPs.
- Keep local overrides small enough to rebase after native upgrades.
- If an override conflicts with a newer native SOP after platform upgrade, stop and ask the operator whether to rebase, retire, or keep the override.
- Report clearly whether the improvement was only proposed or is active as a local override.
