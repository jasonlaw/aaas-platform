# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

## 0.19.3 - 2026-07-08

### Fixed

- **`platform/sop/onboard-tenant.md` — a `validate_install()` check that was
  always failing on a fresh install, before the admin agent's own setup
  even started.** Step 4.1 was reworded to delegate the tenant knowledge
  vault scaffold to `backfill-tenant-vault.sh`, dropping the literal
  mention of `vault-init-tenant.sh` (the script it invokes internally)
  that the validator required. Added a sentence naming `vault-init-tenant.sh`
  explicitly so the validator passes and the delegation is documented.

## 0.19.2 - 2026-07-08

### Removed

- **Admin agent's platform-level knowledge vault** (the Obsidian-compatible
  second brain previously scaffolded at `/opt/aaas/platform/vault` and
  synced from task reports). Removed entirely: `scripts/vault-init.sh`,
  `skills/query-knowledge-vault.md`, and `sop/sync-knowledge-vault.md` are
  deleted, along with every reference to them in `PLATFORM-REFERENCE.md`,
  `admin-hermes/SOUL.md.template`, `sop/write-report.md`,
  `sop/improve-sop.md`, `sop/troubleshoot-tenant.md`,
  `skills/handle-tenant-request.md`, `scripts/setup-platform.sh` (asset
  list, directory scaffold, install step, and validation checks), and
  `docs/architecture.md`/`docs/setup-flow.md`. The admin agent now relies
  solely on `/opt/aaas/platform/reports/INDEX.jsonl` and
  `analyze-reports.sh` for prior-history lookups instead of a separate
  vault layer. **This does not affect the tenant knowledge vault** — each
  tenant's own vault at `/opt/aaas/tenants/{tenant-id}/vault`
  (`vault-init-tenant.sh`, `provision-tenant-vault`,
  `deprovision-tenant-vault`, `backfill-tenant-vault.sh`, and everything in
  `docs/architecture.md`'s Tenant Knowledge Vault section) is untouched and
  remains tenant-agent-only, as before.

## 0.19.1 - 2026-07-07

### Fixed

- **Docker 29.x custom bridge networks (e.g. `agent-vault-net`) can lose
  internet access, on any host, not only Docker Desktop/WSL2.**
  `iptables-legacy` does not fix this — Docker manages its own nftables
  ruleset for bridges regardless of the iptables alternative. Added
  `platform/scripts/fix-docker-nftables.sh` (`--check` / `--apply` /
  `--install`) to detect and permanently fix missing `DOCKER-FORWARD`,
  `DOCKER-CT`, and `POSTROUTING` masquerade rules. Wired into
  `sop/setup-agent-vault.md` (new step 6.5) and `scripts/preflight-check.sh`
  (new warning check). Corrected the misleading iptables-legacy claims in
  `PLATFORM-REFERENCE.md` and broadened `docs/troubleshooting.md`'s nftables
  entry from WSL2-only to all Docker 29.x hosts.
- **Admin Hermes Telegram gateway could fail its first start.** The
  gateway's lazy dependency install for `python-telegram-bot` races its own
  startup check. `skills/setup-admin-hermes.md` Step 1 now pre-installs
  `hermes-agent[messaging]` during runtime setup, before the gateway is
  ever started.

## 0.19.0 - 2026-07-07

### Removed

- **Business intelligence sub-agent and vault-seeding pipeline**
  (`platform/scripts/run-business-research-subagent.py`,
  `platform/tenant-hermes/scripts/seed-vault-context.py`,
  `platform/skills/research-tenant-business.md` — all replaced with
  `To be removed.` stubs). This pipeline ran an LLM synthesis pass during
  onboarding and pre-wrote `Reference/Business Overview.md`,
  `Reference/Vertical Playbook.md`, and `Recurring/Patterns to Watch.md`
  into the tenant's knowledge vault, plus an "Assistant Context" section
  into `business-data.md`, before the tenant ever spoke to the agent.
  This directly conflicted with the knowledge vault's own design
  principle — nothing is pre-seeded, every fact comes from real
  conversation with the owner — so the conflict is resolved by removing
  the pipeline rather than narrowing its scope.

### Changed

- **`business-data.md` merged into the knowledge vault.** There is no
  longer a separate `files/assets/business-data.md` file or "Assistant
  Context" section. Current operational facts (prices, hours, menu,
  availability) now live in the vault at `Reference/Business Data.md`,
  scaffolded as an empty, owner-editable stub during onboarding
  (`vault-init-tenant.sh`) and always re-read by the tenant agent before
  answering a related question — same rule as before, one system instead
  of two. Onboarding no longer collects or classifies operational details
  from the operator at all (`sop/onboard-tenant.md` step 1.2's
  `OPERATIONAL_DETAILS` classification is removed); the tenant agent
  learns these facts itself, from the owner, at runtime. Updated
  everywhere this distinction was previously documented:
  `SOUL.md.template`, `vault-init-tenant.sh`, `docs/architecture.md`,
  `docs/setup-flow.md`, `platform/PLATFORM-REFERENCE.md`,
  `platform/harness/ACCEPTANCE.md.template`, `platform/harness/check-tenant.sh`,
  `platform/policy/platform-policy.yaml`,
  `platform/admin-hermes/MEMORY.md.template`,
  `platform/sop/troubleshoot-tenant.md`, `scripts/setup-platform.sh`'s
  install-time SOUL template validation.
- **The tenant agent builds vault knowledge gradually, with no pressure on
  the owner.** `SOUL.md.template` is now explicit that the agent should
  never ask for a batch of business details up front or make the owner
  feel interviewed — it notes things as they come up in normal
  conversation over days and weeks. This applies equally to
  `Reference/Business Data.md` and to any other vault note.
- **`sop/onboard-tenant.md` simplified.** Step 1.1 (web research) is now
  scoped to brand tone and colour only — it no longer extracts or
  records business facts. Step 1.15 (sub-agent) is removed entirely.
  Step 1.2 generates the capability/brand blocks by cold generation from
  the operator's own interview answers, same as the pipeline's own
  fallback path did before, and no longer collects operational details.
  Step 4.1 (was 4.2) scaffolds the vault empty — no seed notes, no
  business-data.md — and, if the operator gave a business description or
  links in step 1, writes them verbatim into a single
  `Reference/Onboarding Notes.md` note marked `status: unconfirmed`. Step
  17's welcome message frames the agent as new to the business, not
  pre-loaded with it, and says it will look at any given links itself and
  confirm what it finds, without pressure to cover everything in the
  first conversation. Step 19's task report no longer includes sub-agent
  status/confidence fields or a separate business-data.md line.
- **Added an optional "Website / social links" field** to the Phase 2
  interview in `onboard-tenant.md`, so an operator who has a homepage or
  social page on hand can hand it to the agent — as a pointer for the
  agent to look at itself in conversation, not as onboarding research
  input.
- **`SOUL.md.template`** now tells the tenant agent to check
  `Reference/Onboarding Notes.md` (if present) and confirm anything in it
  with the owner when it's natural to do so — not necessarily in the
  first conversation — rather than treating it as settled.
- **`docs/architecture.md`** — replaced the "Vault scaffolding and seed
  notes" / "Business intelligence sub-agent" sections with a single
  "Vault scaffolding" section describing the empty-start design and the
  optional onboarding-source note.
- **`README.md`**, **`platform/PLATFORM-REFERENCE.md`** — removed
  mentions of the business intelligence sub-agent and vault seeding.
- **`platform/scripts/install-tenant-scripts.sh`**,
  **`scripts/setup-platform.sh`** — stopped installing/copying the
  removed scripts and skill file.
