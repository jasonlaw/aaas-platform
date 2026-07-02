---
name: query-knowledge-vault
description: Search the Obsidian knowledge vault at /opt/aaas/platform/vault for prior incidents, tenant history, and SOP friction before troubleshooting, onboarding, or proposing a platform change — and before answering ANY operator question about a specific tenant, past incident, or recurring topic, even in casual conversation that never becomes a formal SOP run. Use when the operator asks "have we seen this before", "check the vault", "what do we know about tenant X", before starting troubleshoot-tenant.md or improve-sop.md, or any time you're about to answer from memory/assumption about something the vault might already have a documented answer to.
---

Before treating an issue as new, check whether the second brain already has
an answer.

**This is not only a pre-SOP step.** A quick grep costs one tool call.
Casual back-and-forth with the operator is exactly where this gets skipped
in practice — "hey, has tenant X had this Telegram issue before?" asked in
passing gets the same check as if the operator had formally started
`troubleshoot-tenant.md`. If a message references a specific tenant, a past
incident, or something that sounds like it might have come up before, check
the vault before answering, not just before running a named SOP.

**Scope: this skill is for the admin agent** (OpenCode or Hermes admin),
searching the platform-level vault at `/opt/aaas/platform/vault` on the host.
It has
nothing to do with any tenant's own knowledge vault at
`/opt/aaas/tenants/{tenant-id}/vault/` (mounted into that tenant's container
at `/home/hermes/vault/`) — that vault is searched by the tenant agent
itself, using its own shell access, following the instructions in its
`SOUL.md`, not this skill. The admin agent has no access to a tenant
container's filesystem and should never attempt to read or write a tenant's
vault directly.

## Steps
1. If `/opt/aaas/platform/vault` does not exist yet, say so and stop - there
   is nothing to query. Suggest running
   `/opt/aaas/platform/scripts/vault-init.sh` if the operator wants to start
   one.
2. Search by keyword across the vault first:
   `grep -ril "{keyword}" /opt/aaas/platform/vault --include='*.md'`
   Try a few keyword variants (error text, tenant ID, SOP name, symptom)
   rather than a single exact phrase.
3. If a tenant ID is involved, read `Tenants/{tenant-id}.md` directly if it
   exists - it is the fastest path to that tenant's history.
4. If the keyword search surfaces an incident note, read it fully and follow
   its `[[links]]` to the related tenant and SOP notes - the answer is often
   in a linked note, not the first match.
5. If the keyword search surfaces a `SOPs/{sop-name}.md` note, read it before
   running that SOP - it may record a known gotcha the native SOP text
   doesn't cover yet.
6. Summarize what you found for the operator before proceeding: cite which
   vault note(s) informed your next step, or state plainly that the vault
   had no relevant history and this is a new issue.
7. After resolving the issue, follow `/opt/aaas/platform/sop/sync-knowledge-vault.md`
   to write back what was learned, so the next search finds it.

## Notes
- This is a read-first habit, not a blocking gate - if the vault is empty or
  irrelevant, say so in one line and move on to the normal SOP.
- Do not treat an absence of vault notes as evidence the issue never
  happened before - the vault only contains what was deliberately written
  down. Cross-check `INDEX.jsonl` via `analyze-reports.sh` for anything the
  vault might be missing.