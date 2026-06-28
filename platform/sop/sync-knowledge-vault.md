# SOP: Sync Knowledge Vault

## Purpose
Turn task reports and operational findings into durable, linked notes in the
platform's Obsidian-compatible knowledge vault at `/opt/aaas/platform/vault`.

The vault is the platform's second brain. It is not a replacement for
`/opt/aaas/platform/reports/` (the full audit trail) or `INDEX.jsonl` (the
machine-readable index) - it is a curated, cross-linked layer on top of them,
meant for a human operator to open in the Obsidian app, browse, search, and
follow links between tenants, incidents, and recurring SOP friction.

Treat the vault as **plain Markdown only**. Never add Obsidian community
plugins, never write non-Markdown binary state into it, and never assume a
running Obsidian process - the agent only ever reads and writes `.md` files
on disk. The operator opens the same folder in their own Obsidian app
whenever they like; the agent does not launch or control Obsidian itself.

## When Required
Run this SOP:
- After writing a task report (`write-report.md`) for any of: tenant
  onboarding, offboarding, a troubleshooting session with a root cause, an
  incident response, or an SOP improvement.
- When the operator asks to "save this to the vault", "write this down",
  "remember this for next time", or similar.
- As the last step of `improve-sop.md`, to link the proposal/override to the
  evidence that justified it.

Do not run this SOP for routine, no-news health checks or onboarding steps
that produced no new operational insight - the vault is for durable
knowledge, not a mirror of every report. If nothing would be worth reading
six months from now, skip it.

## Vault Layout
```
/opt/aaas/platform/vault/
  Home.md                        # entry point, links to the sections below
  Tenants/{tenant-id}.md         # one evolving note per tenant
  Incidents/{timestamp}-{slug}.md
  SOPs/{sop-name}.md             # accumulated learnings per SOP, not the SOP itself
  Platform/{topic}.md            # architecture decisions, version history notes
  Daily/{YYYY-MM-DD}.md          # optional running log, one per day touched
```
The native SOP text itself stays in `/opt/aaas/platform/sop/` - `SOPs/*.md` in
the vault holds only accumulated commentary, gotchas, and links to incidents,
never a duplicate copy of the SOP instructions.

## Steps
1. Confirm the vault exists: `[ -d /opt/aaas/platform/vault/.obsidian ]`. If
   missing, run `/opt/aaas/platform/scripts/vault-init.sh` to scaffold it,
   then continue.
2. Identify which note(s) this update touches. Most updates touch more than
   one:
   - A tenant-specific finding -> `Tenants/{tenant-id}.md`
   - An incident or root-caused failure -> a new `Incidents/{timestamp}-{slug}.md`
   - A recurring SOP friction point -> `SOPs/{sop-name}.md`
   - A platform-wide decision or version note -> `Platform/{topic}.md`
3. For a **new** incident note, use this frontmatter and structure:
   ```markdown
   ---
   type: incident
   created_utc: "{YYYY-MM-DDTHH:MM:SSZ}"
   platform_version: "{contents of /opt/aaas/platform/VERSION}"
   tenant_id: "{tenant-id-or-platform}"
   related_sop: "{sop-name-or-empty}"
   status: "resolved|open|monitoring"
   ---

   # {Short Title}

   ## What Happened
   ## Root Cause
   ## Fix Applied
   ## Links
   - [[Tenants/{tenant-id}]]
   - [[SOPs/{sop-name}]]
   - Report: `/opt/aaas/platform/reports/{report-filename}.md`
   ```
4. For an **existing** tenant or SOP note, append a dated entry rather than
   rewriting history:
   ```markdown
   ## {YYYY-MM-DD}
   Short note. Link the report and any incident: [[Incidents/{...}]]
   ```
   If the note does not exist yet, create it with a one-line frontmatter
   block (`type: tenant` or `type: sop-notes`) and a `## Overview` section
   before the first dated entry.
5. Always link both directions where it makes sense: a tenant note links to
   the incidents that touched it; an incident note links back to the tenant
   and the SOP involved. Use Obsidian wiki-link syntax `[[Note Name]]`
   (relative to the vault root, no `.md` extension, no leading slash).
6. Update `Home.md` only when adding a brand-new top-level area is genuinely
   useful for navigation - do not rewrite it on every sync.
7. Never put secrets, API keys, tokens, or customer private data in any vault
   note. Apply the same redaction discipline as `write-report.md`.
8. This SOP does not require its own task report - it is normally the last
   step of another SOP's report-writing flow. If run standalone at the
   operator's request, a one-line confirmation of what was written is
   sufficient; a full report is not required.

## Rules
- Never store secrets in the vault.
- Never duplicate the full text of a native SOP into `SOPs/{sop-name}.md` -
  link to the source file instead, and only record commentary that adds
  context the SOP file itself does not have.
- Prefer appending dated entries over rewriting existing note history, so the
  note itself becomes a timeline.
- Keep notes short and link out rather than writing long prose in one place -
  the value of a second brain is the link graph, not any single note's
  length.
- If a note would duplicate something `INDEX.jsonl` already captures
  losslessly in structured form, do not create it - only write notes that add
  judgment, narrative, or cross-links a JSON line cannot carry.
- The vault is additive and never blocks SOP completion. If
  `vault-init.sh` is unavailable or the vault directory cannot be written,
  report it as a minor follow-up and continue - never fail an operational
  SOP because the vault sync step failed.
