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
  that the validator required — the same regression class fixed once
  before in 0.15.9. Added a sentence naming `vault-init-tenant.sh`
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

## 0.18.14 - 2026-07-07

### Changed

- **Shortened `setup-admin-hermes.md`'s anti-detour rule to one sentence**
  per feedback that the tooling-affordance explanation was unnecessary
  detail — the objective is simple enough to state directly: if a
  question expects the operator to provide a value, let them type it
  right there; never add a button that detours back to asking again.

### Reviewed

- **`sop/onboard-tenant.md`'s tenant interview questions** for the same
  pattern. Structurally different from admin setup's per-item questions
  — Phase 1 and Phase 2 are each one grouped chat message covering
  several fields at once, not individual button-based prompts, so the
  redundant-option pattern doesn't arise the same way. The one genuine
  options-only field (Telegram home channel single-select) was already
  correctly scoped with no free-text duplicate, matching the admin
  skill. Added one sentence to the Design principle making both points
  explicit: never split these into per-item button questions, and never
  add an "I'll provide it" button in front of a field already asking for
  a value.

## 0.18.13 - 2026-07-07

### Changed

- **Refined `setup-admin-hermes.md`'s anti-redundant-options rule once
  more** after feedback distinguishing the tool's own default free-text
  affordance (unavoidable, out of scope, fine to ignore) from the actual
  defect: an *agent-added* listed option like "I'll provide it" for a
  question expecting a provided value. That kind of option doesn't
  collect an answer — tapping it just defers to asking again, turning
  one question into two round-trips. Rewrote the rule to target this
  precisely: whenever the operator is expected to supply a value
  directly, ask plainly and accept the answer in the same turn via the
  tool's native entry, rather than inserting an extra "I'll provide it"
  confirmation step in front of it.

## 0.18.12 - 2026-07-07

### Changed

- **Clarified `setup-admin-hermes.md`'s anti-redundant-options rule** after
  feedback that 0.18.10/0.18.11's wording could be read as "avoid buttons
  generally," which was never the intent. Buttons for a genuinely fixed
  set of answers (e.g. the provider list) are correct and expected — the
  only banned thing is two options that both mean "let the operator type
  something" (e.g. "I'll provide it" next to "type your own answer").
  Rewrote the rule to say this explicitly, using the reported phrasing
  as the named example, and restated the two concrete cases: a pure
  free-text field (API key, model name) gets zero buttons, full stop; an
  open-set field (provider list) gets its named options plus exactly one
  "something else" choice, never two.

## 0.18.11 - 2026-07-07

### Fixed

- **Every question in `setup-admin-hermes.md`'s Ask The Operator section
  now individually forbids the redundant-free-text-option pattern**, not
  just the one general rule added in 0.18.10. 0.18.10 fixed the two
  reported examples (API key, fallback provider) and added one general
  rule at the top of the section; this pass (run against OpenCode, which
  executes this setup and renders its own question UI, not Hermes)
  annotates all 7 top-level items and every sub-field individually, so
  no single item depends on the general rule alone to avoid the pattern:
  - Items 2, 3, 4's fallback model/key, 5's host/port, 7's bot
    token/allow list — each now says "plain free text, no options UI"
    directly on the item, not just implied by being unmarked.
  - Items 1 and 4 — each now states directly that its "other" catch-all
    is the single free-text escape hatch, not to be duplicated with a
    second "type your own" option.
  - Items 6 and 7's top-level yes/no — each now states directly that
    it's a plain two-way choice with no free-text answer of any kind.
  - The Telegram home-channel single-select — now states directly that
    the only valid answers are the already-collected allow-list IDs, no
    "other" and no free-text option belongs on it at all.
  - Confirmed no other operator-facing question exists anywhere else in
    the file outside this section.

## 0.18.10 - 2026-07-07

### Fixed

- **`setup-admin-hermes.md`'s Ask The Operator questions were being
  presented with redundant duplicate free-text options.** Reported from
  a live run: the API key question (item 3, already marked pure
  free-text with no options) was shown as a choice between "I'll provide
  it" and "type your own answer" — two buttons for the same action. The
  fallback provider question (item 4, which already lists concrete
  providers plus a single "other" catch-all) was shown with an *extra*
  "type your own answer" option alongside "other," again duplicating the
  same escape hatch. Added an explicit rule: free-text items get no
  options UI at all, and an "other"-style catch-all is exactly one
  free-text escape hatch, never two side by side.

## 0.18.9 - 2026-07-07

### Fixed

- **`scripts/agent-vault-health.sh`'s MITM proxy port check false-failed on
  a healthy proxy.** An operator-submitted bug report correctly identified
  the symptom (line 57's `[ "$PROXY_CODE" = "407" ]` never matched even
  when the proxy was up and correctly returning 407) but misdiagnosed the
  cause and proposed a fix that doesn't work — verified by reproducing
  against a real proxy response (one-shot `nc` responder returning actual
  407s) rather than reading the script alone:
  - The report blamed line 54's `|| echo '000'` for "overriding" a 407
    that curl had already captured. Tested directly: curl's
    `%{http_code}` is **always** `000` for a failed CONNECT tunnel, with
    or without the shell fallback — it reflects the final destination
    resource's response (never reached here), not the proxy's own CONNECT
    response. The correct variable is `%{http_connect}`, which the report
    never identified.
  - The report's proposed fix (`|| true` + default-if-empty, keeping
    `%{http_code}`) was tested exactly as written: still produces `000`.
    Applying it as submitted would have left the check permanently
    broken.
  - A second, compounding bug the report missed: even switching only to
    `%{http_connect}` while keeping `|| echo '000'` produces `407000` —
    curl's real value with the shell fallback still appended after it
    (curl's own exit code is non-zero — confirmed 56, "CONNECT tunnel
    failed," not the reported 7 — even when it already wrote a valid
    code to stdout). Both the `-w` variable and the exit-code handling
    had to be fixed together.
  - Fix: switched to `%{http_connect}`, and separated exit-code handling
    from output capture (`set +e` around the bare assignment, default to
    `000` only if the variable ends up empty) instead of an inline `||`.
    Verified against a healthy 407-returning proxy (PASS), a genuinely
    unreachable proxy (FAIL, no regression), and confirmed compatible
    with the script's existing `set -euo pipefail`.

## 0.18.8 - 2026-07-06

### Changed (streamlining pass — no behavior changes)

Went through every rule and prompt touched across 0.18.3–0.18.7 and
removed historical/justification narrative ("this used to be done via
X," "a live setup report confirmed," "this is correct, not a
misconfiguration," version-number call-outs explaining why something
changed) in favor of stating the current rule directly. The underlying
mechanism, commands, file paths, and cross-references are unchanged —
this is a clarity pass, not a behavior change.

- **`skills/configure-telegram-channel-admin.md`** rewritten: dropped
  the "Why this exists" history section (retired-sed-approach backstory,
  routing-rule "this is correct not a misfire" reassurance) in favor of
  a short "Rule" statement. 158 → 114 lines, same steps/inputs/verify
  commands.
- **`tenant-hermes/skills/configure-telegram-channel-tenant.md`**
  rewritten the same way for consistency with the admin skill.
- **`skills/setup-admin-hermes.md`**: removed the retired-venv-install
  backstory (Step 1), the "previous version used nohup" aside (Step 7),
  the "this already happened once for real: 0.13.1/0.13.2" narrative
  (Step 6), and tightened several other paragraphs that had grown
  duplicative across recent patches. 838 → 811 lines. Fixed a
  now-broken "see that skill's Why this exists" cross-reference left
  over from the configure-telegram-channel-admin.md rewrite.
- **`sop/provision-tenant-vault.md`**: reworded the "old
  connect-Agent-Vault-itself design" migration note, the "unlike
  earlier Agent Vault versions" CLI-history aside, and the "same reason
  required in earlier platform versions" network-naming note into
  direct present-tense rules/checks.
- **`scripts/provision-tenant-vault.sh`**: trimmed the `provider_id()`
  comment's "confirmed-consistent derivation rule" phrasing to state
  the rule directly.
- **`admin-hermes/config.yaml.template`** and
  **`tenant-hermes/config.yaml.template`**: replaced the "may or may
  not be where this Hermes version persists the home channel" hedge on
  `home_chat_id` with a direct instruction (never fill in by hand, set
  via `hermes config set`, verify via `hermes config get`) — the hedge
  added no actionable information over the direct rule.
- **`PLATFORM-REFERENCE.md`**: removed two bug-history narratives (the
  `MANAGED_ASSET_RELATIVE_PATHS` drift story, the watchdog
  `local/watchdog.env`-to-systemd-override migration story), keeping
  only the current rule in each case.

Verified after every edit: all shell/Python scripts still parse, all
YAML still parses, no new broken cross-references, and no remaining
"Why this exists" references to the now-removed sections.

## 0.18.7 - 2026-07-06

### Fixed (found during a full project audit of 0.18.4–0.18.6)

- **`admin-hermes/env.template`'s own Telegram comment still asserted the
  old, wrong claim** that `config.yaml`'s `home_chat_id` "is never read by
  the gateway" — this was already corrected in `setup-admin-hermes.md` and
  `config.yaml.template` in 0.18.5/0.18.6, but the same claim was left
  standing in `env.template`, contradicting the fix. Rewritten to match:
  either file may be where `hermes config set` puts
  `TELEGRAM_ALLOWED_USERS`/`TELEGRAM_HOME_CHANNEL`, both are correct, and
  `hermes config get` — not reading the file — is the way to verify.

- **`configure-telegram-channel-admin.md` pointed at the wrong file for
  its pre-0.13.1 Hermes escalation note.** It said "see
  `admin-hermes/env.template`'s note on this," but that note actually
  lives in `setup-admin-hermes.md` Step 6 — `env.template` has never
  contained it. Fixed the cross-reference.

- **`tenant-hermes/skills/configure-telegram-channel-tenant.md`'s Step 4
  test message didn't prefer `HOME_CHANNEL`** even when the call being
  verified had just set one, unlike the admin skill's equivalent step.
  Now uses `${HOME_CHANNEL:-one-allowed-id}`. Also completed two small
  gaps left from the 0.18.6 home-channel addition: the Preconditions
  bullet and Inputs section now both mention home channel alongside bot
  token and allow list, matching what Steps 1–3 already implement.

### Verified, no changes needed

- Re-ran the full cross-reference audit from 0.18.6 after these fixes;
  confirmed no remaining stale "tenant has no home channel" or "gateway
  never reads / dead config" claims anywhere in the repo, and no new
  broken `.md`/`.sh`/`.py`/`.yaml` cross-references.
- Validated YAML syntax on every non-templated `.yaml` file and
  structural sanity on the four `config.yaml.template` files (which
  contain `{{ }}` placeholders and can't be parsed as plain YAML).
- Re-ran `bash -n` / `py_compile` on every shell and Python script in the
  repo, not just the ones touched this round.
- Confirmed the `Never` sections of the admin and tenant Telegram skills
  make the same claims about `.env`/`config.yaml` routing, with no
  contradictions between them.

## 0.18.6 - 2026-07-06

### Fixed

- **`setup-admin-hermes.md` Ask The Operator item 7 could be read as
  multi-select for `TELEGRAM_HOME_CHANNEL`.** It accepts exactly one
  primary contact, never a list. Reworded to say explicitly that it's a
  single-select choice when the allow list has more than one ID.

- **Admin Hermes had no explicit guard against lazy-install
  configuration.** `HERMES_LAZY_INSTALL_TARGET` /
  `HERMES_DISABLE_LAZY_INSTALLS` exist solely to work around the tenant
  containers' read-only image; admin Hermes runs on the host with a
  normal, writable venv and never needs them. Added an explicit
  Preconditions rule against configuring either for admin Hermes.

- **Tenant Telegram onboarding had no `TELEGRAM_HOME_CHANNEL`
  equivalent.** Added it end-to-end using the same convention as admin
  Hermes: single ID, auto-selected if the allow list has exactly one
  entry, asked as a single-select choice otherwise. Updated
  `tenant-hermes/env.template` (new commented field),
  `sop/onboard-tenant.md` (collect at step 1, render + verify at steps
  5/6), `tenant-hermes/skills/configure-telegram-channel-tenant.md`
  (full rotation support: inputs, sanity checks, write, verify, `Never`
  rules), `tenant-hermes/config.yaml.template`'s `home_chat_id` comment,
  and `skills/configure-telegram-channel-admin.md`'s two stale
  "tenants never have a home channel" claims.

- **"Vertical" was renamed to "industry" throughout the tenant
  onboarding pipeline** (obsoleted term). Case-preserving rename across
  12 files: `sop/onboard-tenant.md`, `sop/update-tenant.md`,
  `sop/troubleshoot-tenant.md`, `skills/research-tenant-business.md`,
  `tenant-hermes/MEMORY.md.template`, `tenant-hermes/SOUL.md.template`,
  `tenant-hermes/evals/_fixed-safety-v1.yaml`,
  `tenant-hermes/evals/_skill-verification-primitives-v1.yaml`,
  `scripts/generate-platform-eval.sh`,
  `scripts/run-business-research-subagent.py`, `PLATFORM-REFERENCE.md`,
  and `evals/meta-eval-generation-v1.yaml`. Covers both prose ("vertical
  detail" → "industry detail", "cross-vertical" → "cross-industry") and
  the `{{VERTICAL_CAPABILITIES_BLOCK}}` / `{{VERTICAL_BRAND_FACTS_BLOCK}}`
  template placeholders, now `{{INDUSTRY_CAPABILITIES_BLOCK}}` /
  `{{INDUSTRY_BRAND_FACTS_BLOCK}}`. Verified the renamed `.py`/`.sh`
  files still parse.

- **No documented guard against the Hermes CLI prompting for a sudo
  password.** Hermes prompts interactively for sudo (or reads
  `SUDO_PASSWORD`) when a command needs elevation — admin Hermes's whole
  design avoids sudo for anything agent-driven, so this should never
  fire. Added an explicit Preconditions rule: never set `SUDO_PASSWORD`;
  treat a sudo prompt as a bug to fix, not something to paper over.

- **Two broken self-references in `setup-admin-hermes.md`.**
  `configure-telegram-channel.md` (missing the `-admin` suffix) appeared
  twice, pointing at a file that doesn't exist. Fixed both to
  `configure-telegram-channel-admin.md`.

- **Streamlined Step 3.1's routing-rule explanation.** Items 1 and 2 had
  grown duplicative across recent patches (the same secrets-vs-`.env`
  rule explained three times in adjacent paragraphs). Condensed to state
  the rule once and point to `configure-telegram-channel-admin.md` for
  the full rationale, with no loss of the underlying guidance.

- Verified, via a full pass over every `` `path` `` and `` /opt/aaas/... ``
  reference in the changed skills/SOPs, that no new broken cross-file
  references were introduced by this or the prior two releases.

## 0.18.5 - 2026-07-06

### Fixed

- **Telegram config skills (admin and tenant) wrongly assumed
  `TELEGRAM_ALLOWED_USERS` / `TELEGRAM_HOME_CHANNEL` always land in
  `.env`.** A live setup report showed `hermes config set` writing these
  two keys to `config.yaml` instead, which 0.18.3/0.18.4 treated as a
  bug and worked around with a manual `.env` edit — reintroducing the
  exact hand-editing risk that version existed to remove. Confirmed
  against Hermes's own documented convention: `hermes config set` routes
  **secrets to `.env`, everything else to `config.yaml`** — not by
  whether the key name looks env-var-shaped. `TELEGRAM_BOT_TOKEN` is a
  credential and lands in `.env`; `TELEGRAM_ALLOWED_USERS` and
  `TELEGRAM_HOME_CHANNEL` are access/behavior settings, not secrets, and
  may correctly land in `config.yaml` instead. This is expected behavior,
  not a misconfiguration. Updated `skills/configure-telegram-channel-admin.md`,
  `tenant-hermes/skills/configure-telegram-channel-tenant.md`,
  `skills/setup-admin-hermes.md` (Step 3.1 and Step 6), and
  `admin-hermes/config.yaml.template`'s `home_chat_id` comment to stop
  asserting a fixed destination file, verify only via `hermes config get`
  (which is correct regardless of which file backs a key), and explicitly
  forbid moving a value between `.env` and `config.yaml` after
  `hermes config set` writes it.

- **Agent Vault `--auth-type Bearer` used the wrong case.** The CLI
  requires lowercase `bearer`; every call site used title-case `Bearer`,
  which a live setup report confirmed fails and had to be corrected by
  hand. Fixed all six occurrences: `sop/provision-tenant-vault.md` (×2),
  `skills/manage-agent-vault.md`, `skills/setup-admin-hermes.md` (×2),
  and `scripts/provision-tenant-vault.sh` (×2).

- **Agent Vault service registration used an env-var-shaped name for
  `--name`, which Agent Vault rejects.** `--name` requires lowercase
  alphanumeric-and-hyphens only; every call site passed the credential's
  env var name directly (e.g. `OPENCODE_ZEN_API_KEY`), confirmed failing
  in the same live setup report (worked around manually by registering
  `opencode-zen` / `openrouter` instead). `--token-key` and
  `credential set` correctly keep using the env var — only `--name` was
  wrong. Fixed in `skills/setup-admin-hermes.md` (Step 5.2/5.3/5.7),
  `skills/manage-agent-vault.md` (Section 2.1/2.3), and
  `sop/provision-tenant-vault.md` (Section 2/2.1) by introducing a
  distinct `{PROVIDER_ID}` / `{FALLBACK_PROVIDER_ID}` placeholder (the
  catalog's Provider ID column) for `--name`, separate from
  `{PROVIDER_VAR}`. `scripts/provision-tenant-vault.sh` only receives the
  env var as input, so it now derives the service name in code via a new
  `provider_id()` function that mechanically reverses the catalog's own
  documented, confirmed-consistent derivation rule (`ENV_VAR =
  PROVIDER_ID.upper().replace('-','_') + '_API_KEY'`) — e.g.
  `OPENCODE_ZEN_API_KEY` → `opencode-zen` — rather than requiring a new
  script argument.

- **`setup-admin-hermes.md` Step 7's Vite-build wait guidance was
  vulnerable to a restart race.** The dashboard's first-start build can
  occasionally exceed the documented ~60s, and nothing warned against
  restarting the systemd unit while waiting — a premature restart
  re-triggers the build from scratch, turning a one-time wait into a
  restart loop that never completes (matching a live setup report of a
  manual pre-build workaround being needed). Widened the poll window from
  40×2s (80s) to 60×3s (3 minutes), added an explicit "do not restart
  while waiting" warning explaining why a restart makes it worse, and
  added guidance to check `systemctl --user status` for an actual
  crash loop before assuming the build itself is hung.

## 0.18.4 - 2026-07-06

### Fixed

- **`platform/admin-hermes/env.template` — `OPENCODE_GO_API_KEY` placeholder
  was missing.** `env.template` had commented-out placeholder lines for
  `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `NOUS_API_KEY`,
  and `OPENCODE_ZEN_API_KEY`, but not `OPENCODE_GO_API_KEY`, which has been a
  first-class entry in `reference/llm-provider-catalog.md` since it was added.
  The Step 6 key-presence loop in `setup-admin-hermes.md` checks `admin/.env`
  against keys found in `env.template` — so an admin instance configured with
  `opencode-go` as its provider would never fail that check even if the key
  line was absent from `.env`, because the template itself was missing it.
  Added `# OPENCODE_GO_API_KEY=routed-via-agent-vault` immediately after the
  `OPENCODE_ZEN_API_KEY` line, matching the pattern of every other provider
  placeholder in the file.

- **`platform/skills/setup-admin-hermes.md` Step 6 — "Telegram left disabled"
  verification was brittle against `hermes config set` state.** The check
  `grep -q "^# TELEGRAM_BOT_TOKEN=" admin/.env` only passes when the line is
  present and commented with exactly `# TELEGRAM_BOT_TOKEN=`. After `hermes
  config set` touches the file (e.g. from a prior run or a rotation attempt
  that was aborted), the line shape may differ or the key may be absent
  entirely — both cases silently fail the `grep` even though no token is
  actually configured. Replaced with a `hermes config get` call that checks
  whether the key has a live value, consistent with how the Telegram-enabled
  path already verifies the three keys, and independent of `.env` line
  formatting.

- **`platform/skills/configure-telegram-channel-admin.md` Step 3 — allow-list
  and home-channel verification was prose-only.** The step said to "compare
  `$ALLOWED_USERS`" and "verify `$HOME_CHANNEL`" but left both as comments,
  not executable shell. A truncated or reordered allow list would still print
  as "non-empty" with no mismatch surfaced. Replaced both verification comments
  with explicit shell comparisons (`[ "$WRITTEN" = "$EXPECTED" ]`) that print
  `OK` or `FAIL` with the written vs expected values, consistent with the
  verification style used throughout the rest of the platform skills.

## 0.18.3 - 2026-07-06

### Changed

- **Admin Telegram setup now writes credentials via the official
  `hermes config set` CLI instead of `sed -i` against commented-out
  placeholder lines in `.env`.** `sed`-based writes only work as long as
  the target line's exact shape never drifts, which had already been a
  source of setup inconsistency. New skill:
  `platform/skills/configure-telegram-channel-admin.md`, called from
  `setup-admin-hermes.md` Step 3.1. Also replaces that step's grep-based
  verification with `hermes config get`.
- **Added `platform/tenant-hermes/skills/configure-telegram-channel-tenant.md`**
  for reconfiguring an already-onboarded, already-running tenant's
  Telegram bot token or allow list via `docker exec {container} hermes
  config set`, instead of hand-editing the tenant's bind-mounted `.env`.
  This is deliberately a separate skill from the admin one above, not a
  shared one with a mode switch: admin Hermes is host-installed and
  `hermes` is reachable directly, while a tenant's `hermes` only exists
  inside its own container image (`/opt/hermes/.venv`, read-only) once
  that container is running — the two have different preconditions,
  different invocation shape (`HERMES_HOME=...` vs `docker exec`), and
  admin always has a home channel while tenants never do.
- **Tenant onboarding's first-ever `.env` write for `TELEGRAM_BOT_TOKEN` /
  `TELEGRAM_ALLOWED_USERS` is unchanged** (still a plain template
  substitution in `sop/onboard-tenant.md` step 5) — at that point in
  onboarding the tenant's container hasn't been created yet, so there is
  no `hermes` process on the host to call. The new tenant skill above only
  applies to *later* reconfiguration of an already-running tenant.

### Fixed

- **`platform/scripts/aaas-watchdog.sh` — every scheduled run failed with
  exit code 1 and wrote no logs, on every fresh install.** Root cause: two
  `grep` calls inside command substitutions, under `set -euo pipefail`, with
  no `|| true` guard. `grep` exits 1 when it finds zero matching lines —
  correct and expected on a platform with no tenants and no admin Hermes
  installed yet (the normal state right after a fresh install) — and
  `pipefail` propagates that as the whole pipeline's exit status, which then
  aborts the entire script under `set -e`, before the log() function is ever
  reached. Reproduced exactly: exit code 1, zero output, matching the
  reported symptom precisely. Fixed both instances by wrapping the `grep` in
  `{ grep ... || true; }`: (1) the `all_entities` build (both the
  admin-Hermes-installed and admin-Hermes-not-installed branches), and (2)
  the `API_SERVER_KEY` extraction in `admin_hermes_is_healthy()`, which has
  the identical failure mode if `admin/.env` exists but doesn't yet contain
  that key (a plausible transient state right after `setup-admin-hermes`
  creates the stub). Audited every other `grep`/`awk`/`cut` usage in this
  file and confirmed no other instances of this pattern exist — `awk` and
  `cut` do not exit non-zero on empty/no-match input the way `grep` does, so
  those call sites were already safe.

- **`scripts/setup-platform.sh` — the generated Agent Vault
  `docker-compose.yaml` carried no `aaas.watchdog` labels at all**, so even
  with the crash above fixed, Agent Vault could never actually be discovered
  or monitored by the watchdog — `docker ps -a --filter
  label=aaas.watchdog=true` matches nothing, `vault_line` is permanently
  empty, and the watchdog's priority-0 gate silently does nothing every
  cycle. This directly contradicts `docs/architecture.md`'s "Agent Vault is
  priority 0 and is checked first" claim, which has never actually been true
  for any platform installed via this script — confirmed via git history
  that these labels were absent as far back as the compose-generation logic
  goes. Added the three required labels (`aaas.watchdog=true`,
  `aaas.watchdog.priority=0`, `aaas.watchdog.playbook=agent-vault-failure.md`)
  to the generated compose file. Verified end-to-end with a mocked `docker`
  CLI: before the fix, `vault_line` is empty and Agent Vault is silently
  unmonitored; after the fix (with the labels present), the same discovery
  pipeline correctly produces `vault_line=[0	agent-vault	agent-vault-failure.md]`.
  **This fix only affects newly generated compose files** — an
  already-running Agent Vault container needs `docker compose -f
  /opt/aaas/agent-vault/docker-compose.yaml up -d --force-recreate
  agent-vault` after pulling this fix, to pick up the new labels. This is
  safe: Agent Vault's data lives in a bind mount
  (`/opt/aaas/agent-vault/data:/data`), not an anonymous volume, so
  `--force-recreate` does not affect stored credentials.

## 0.18.1 - 2026-07-05

### Fixed

- **`scripts/setup-platform.sh` — fresh install could hang silently after
  the "Agent Vault CA certificate not yet present" warning, with no further
  output and no error.** The Agent Vault health check added in 0.17.0 was
  placed unconditionally inside `validate_install()`, which runs on every
  invocation of `setup-platform.sh` — including a normal fresh install, not
  just `--validate-only` as the accompanying comment claimed. On a fresh
  install, Agent Vault's container has only just been started moments
  earlier (its master password isn't set yet, and its API/CLI session may
  not be ready), so this check was both premature and dangerous: its output
  is redirected to `/dev/null` by the caller, so if any step inside
  `agent-vault-health.sh` blocked, the operator would see nothing — not even
  an error — just a frozen terminal. Reproduced and confirmed the specific
  cause: the CLI session check (`agent-vault vault list`) was the only
  network-touching step in `agent-vault-health.sh` without a timeout (every
  other check uses `curl --connect-timeout 5`); against a still-initializing
  or unreachable Agent Vault, it can hang indefinitely. Fixed two ways: (1)
  gated the health check in `setup-platform.sh` to run only when
  `VALIDATE_ONLY=true`, matching what the comment always said it should do;
  (2) wrapped the CLI check in `agent-vault-health.sh` with `timeout 10` as
  defense in depth, so even in `--validate-only` mode this can never hang
  past 10 seconds. Verified with a fake hanging `agent-vault` binary: before
  the fix, the check blocked for the binary's full sleep duration with the
  script's own output suppressed; after the fix, it correctly times out at
  10 seconds and reports `WARN ..._or_timed_out` instead of hanging.

## 0.18.0 - 2026-07-05

### Fixed

- **`platform/tenant-hermes/scripts/reconcile-plugins.sh` — script always exited
  0, even when every plugin reinstall failed.** Individual reinstall failures
  were caught with `||` and downgraded to a `warn` log line, but nothing
  tracked that across the loop, so the script's final statement
  (`log "Reconciliation pass complete."`) always succeeded and became the exit
  code. This made the failure branch in `tenant-entrypoint.sh` (added in
  0.17.0's sentinel fix) permanently unreachable — the sentinel file could
  never actually be written, regardless of how many plugins failed to
  reconcile. Added a `RECONCILE_HAD_FAILURE` flag set on any reinstall
  failure; the script now exits 1 if any entry failed, 0 otherwise. Every
  entry is still always attempted (non-blocking behavior is unchanged) — only
  the final exit code changed. Verified with a live reproduction: a
  mixed-failure manifest now correctly exits 1 and triggers the sentinel;
  an all-success manifest and a missing-manifest case both still exit 0.

- **`platform/harness/check-tenant.sh` — `plugin_manifest_size` check always
  counted 0 plugins.** The grep pattern `'^- '` (anchored at column 0) never
  matched real manifest entries, which are written by `tenant-install.sh` at
  2-space indent (`  - name: "..."`). The check silently reported `PASS 0
  installed plugins` regardless of how many were actually present — the exact
  observability failure this check was added to catch. Fixed to
  `'^  - name:'`, verified against a realistic two-entry manifest fixture
  (now correctly counts 2, previously counted 0).

- **`platform/policy/platform-policy.yaml` — merged `no_credential_in_skills`
  into `no_credential_persistence`.** These two rules were substantially
  redundant: `no_credential_persistence`'s "(2) Nowhere else" clause already
  enumerated skill files, vault notes, and generated files as forbidden
  credential-persistence locations, while `no_credential_in_skills` repeated
  nearly the same list with one genuinely new scenario (posting a credential
  to Telegram/an external channel). Because every rule's `agent_instruction`
  is rendered verbatim into every tenant's `SOUL.md` (per onboard-tenant.md
  step 5.1) and both rules also flow through unchanged into the generated
  `_fixed-safety-v1.yaml` (a pure derivation via `generate-platform-eval.sh`),
  this redundancy was paid twice: once in every tenant's system prompt token
  budget, and once in the generated eval file. Merged the Telegram-posting
  scenario and its `refuses_credential_in_skill_message` eval check into
  `no_credential_persistence`, then removed `no_credential_in_skills`
  entirely. Rule count: 7 → 6. All 12 eval checks preserved (none lost,
  none duplicated) — verified structurally with a Python replica of
  `validate-platform-rules.sh`'s coverage check (6/6 rules fully covered,
  0 failures) since `yq` was unavailable in the audit sandbox. Regenerated
  `_fixed-safety-v1.yaml` accordingly (a faithful line-for-line replica of
  `generate-platform-eval.sh`'s own logic, since the sandbox's network
  restrictions blocked fetching the real `yq` binary) — diff against the
  previous generated file shows pure reordering only, no check gained,
  lost, or altered. Fixed the one stale cross-reference to the removed rule
  id in `_skill-verification-primitives-v1.yaml`'s `credential_scan`
  primitive description.

### Changed

- **`docs/architecture.md`** — documented `reconcile-plugins.sh`'s exit code
  contract now that it's meaningful (previously always 0): `0` = all entries
  OK or not present, `1` = at least one reinstall failed, consumed by
  `tenant-entrypoint.sh`'s sentinel mechanism.

## 0.17.0 - 2026-07-05

### Added

- **`platform/scripts/preflight-check.sh` — `admin_hermes_configured` check.**
  Added a new check that surfaces whether admin Hermes is configured (`admin/config.yaml`
  and `admin/.env` both present) before any operation that depends on it. Previously,
  running the business intelligence sub-agent (onboard-tenant step 1.15) when admin
  Hermes was not set up would silently fall back to cold generation with no diagnostic
  — the sub-agent calls `hermes -z` from the admin install, which requires
  `admin/.env` to be present. Operators now see `WARN admin_hermes_not_configured`
  during preflight rather than a cryptic sub-agent fallback. Warn-only (not fail),
  since preflight is run in contexts other than onboarding where admin Hermes may
  legitimately not be set up yet.

- **`platform/harness/check-tenant.sh` — plugin reconcile failure sentinel check.**
  `tenant-entrypoint.sh` now writes `/opt/data/.reconcile-failed` (with a UTC
  timestamp) when `reconcile-plugins.sh` fails on startup, and removes it on the
  next successful reconcile. `check-tenant.sh` reads this sentinel and emits
  `WARN plugin_reconcile_healthy` with the failure timestamp when present. Previously
  a reconcile failure on startup was only visible in container logs — the watchdog
  and harness both saw a running container and reported healthy. The sentinel makes
  degraded-plugin state observable at harness time without parsing logs.

- **`platform/harness/check-tenant.sh` — plugin manifest size warning.**
  Added an opportunistic warn threshold on the `installed-plugins.yaml` manifest:
  warns at >10 entries (review recommended) and >20 entries (flag clearly). Neither
  threshold blocks onboarding or upgrades. This surfaces manifest accumulation during
  routine health checks rather than waiting for a monitor-health SOP to catch it.

### Fixed

- **`platform/sop/onboard-tenant.md` step 3 — tenant slug collision check.**
  Added explicit collision guards before creating any tenant files: the SOP now
  requires checking both `tenants.yaml` for an existing `id:` entry and the
  `/opt/aaas/tenants/{id}` directory for existence. If either is present, onboarding
  stops and asks the operator for a disambiguating suffix. Previously two tenants
  with identical slug-producing names (e.g. "Happy Paws" and "happy-paws") would
  silently produce the same tenant ID and overwrite each other's directories.

- **`platform/sop/onboard-tenant.md` steps 15–17 — welcome message moved after evals.**
  The Telegram welcome message (previously step 15) now fires *after* the harness
  check (now step 15) and both eval profiles (now step 16), as the new step 17.
  Previously the owner received a welcome message before eval verification, setting
  a false expectation that the bot was fully ready even if evals later failed. A
  gate note was added to step 16 making this ordering requirement explicit.

- **`platform/sop/onboard-tenant.md` step 4.1 — `business-data.md` context section
  deduplication guard.** The "Assistant Context" section append step now first checks
  whether the section already exists (relevant on a re-run after a partial onboarding
  failure) before appending. Previously re-running step 4.1 would produce duplicate
  `## Assistant Context` sections in the file.

- **`platform/sop/onboard-tenant.md` step 4.2 — post-seed vault note enumeration.**
  After `seed-vault-context.py` exits, the SOP now enumerates which `.md` files
  are actually present in the vault and includes the list in the task report. This
  closes a gap where all three seed writes could silently fail but the seeder still
  reported exit 0 (e.g. due to a path mismatch), leaving onboarding marked complete
  with an empty vault and no visible error.

- **`platform/sop/upgrade-platform.md` step 6–7 — `bash <(curl)` not `curl | bash`.**
  Steps 6 and 7 now use `bash <(curl -fsSL ...) --yes` (process substitution) instead
  of `curl -fsSL ... | bash -s -- --yes` (pipe). The pipe form runs the installer in
  a subshell that cannot export PATH or group-membership changes back to the calling
  shell — the same issue `README.md` has always documented, but the upgrade SOP
  itself was still using the wrong form.

- **`platform/sop/upgrade-platform.md` step 12 — replace fragile inline grep/awk
  YAML loop with `upgrade-tenant.sh`.** The one-liner loop that restarted tenants
  after a Docker daemon restart used `grep 'status: active' | awk '{print $2}'` to
  parse `tenants.yaml` — this breaks on multi-line values, inline YAML comments, and
  any key whose value happens to contain the string "active". Replaced with a loop
  that calls `upgrade-tenant.sh` per tenant, which handles image-ID comparison and
  only sets `NEEDS_RECREATE` when something actually changed.

- **`platform/PLATFORM-REFERENCE.md` — `ADMIN_HERMES_API_KEY` explanation added.**
  The credential-by-type rule now explains why `ADMIN_HERMES_API_KEY` in a tenant's
  `.env` correctly bypasses Agent Vault: it is the API server token for the
  tenant-to-admin bidirectional channel, not an LLM key. Agent Vault's MITM proxy
  only handles HTTP/HTTPS calls to LLM providers, so this credential is out of scope
  by design. Previously a security reviewer would have no in-platform explanation for
  why this one credential does not follow the `routed-via-agent-vault` pattern.

- **`scripts/setup-platform.sh` `--validate-only` — Agent Vault health check.**
  Added a call to `agent-vault-health.sh` during `--validate-only` mode. Previously
  `--validate-only` only checked file presence and content — it reported success even
  if Agent Vault was down during a post-upgrade validation run. Warn-only (mirrors
  the posture in `preflight-check.sh`): Agent Vault may not be set up yet on a
  first-run validate.

## 0.16.18 - 2026-07-05

### Fixed

- **`platform/PLATFORM-REFERENCE.md` line 150 — stale `--force-recreate` instruction
  after `SOUL.md` re-render.** The bullet said "After rendering, `--force-recreate`
  the tenant container so it reads the updated `SOUL.md`" — incorrect because
  `SOUL.md` is volume-mounted; the updated file is visible to the container on its
  next restart without a forced recreate. This was the same class of bug caught in
  `upgrade-tenant.sh` (fixed in 0.16.17). Corrected to state that no recreate is
  needed for a `SOUL.md`-only change, and that if a recreate is already happening
  for another reason (new image, `.env` or `config.yaml` change) the updated
  `SOUL.md` is picked up automatically.

## 0.16.17 - 2026-07-05

### Changed

- **`platform/scripts/upgrade-tenant.sh` — SOUL.md policy blocks are now re-rendered
  automatically on every upgrade run**, replacing the manual admin-agent step that
  was previously documented as `upgrade-tenants.md` step 3.1. The script reads
  `platform-policy.yaml` and the tenant's own `tenant-policy.yaml`, extracts each
  rule's `agent_instruction` verbatim, and rewrites only the content between the
  `<!-- BEGIN PLATFORM RULES -->`/`<!-- END PLATFORM RULES -->` and
  `<!-- BEGIN TENANT RULES -->`/`<!-- END TENANT RULES -->` marker pairs in
  `SOUL.md`. All other `SOUL.md` content (capabilities block, brand tone, conduct
  lines set at onboarding) is left exactly as-is. A diff check is run before
  writing — if nothing changed the file is not touched. Because `SOUL.md` is
  volume-mounted, the updated file is visible to the container on its next restart
  without a forced recreate; `NEEDS_RECREATE` is not set for this change alone.
  If a recreate occurs for another reason (image diff, backfill), the updated
  SOUL.md is picked up automatically. `upgrade-tenants.md` step 3.1 (previously
  a manual re-render instruction with a separate `--force-recreate` note) is
  removed and replaced with a description of the new automatic behaviour in step 3.

- **`platform/scripts/upgrade-tenant.sh` — `MEMORY.md` and `USER.md` are
  explicitly never modified during upgrade.** These files are maintained at
  runtime by the tenant agent (Mnemosyne). The script adds a comment block making
  this protection explicit so future contributors cannot accidentally add a
  template-overwrite step. `upgrade-tenants.md` step 3 now documents this
  constraint and the correct operator path for intentional memory updates
  (direct host edit + `seed-mnemosyne.py` re-seed, not an onboarding re-run).

- **`upgrade-tenants.md` step 3.1 removed.** The manual SOUL.md policy re-render
  instruction (and its associated manual `--force-recreate` guidance) is no longer
  needed — the script handles it. Step 3's description updated to cover both the
  automatic SOUL.md re-render and the MEMORY.md/USER.md non-modification guarantee.

## 0.16.16 - 2026-07-05

### Removed

- **`platform/docker/Dockerfile` — dropped the baked-in `himalaya` (email) and
  `faster-whisper` (speech-to-text) tenant capabilities**, along with the
  `himalaya-builder` Rust build stage that compiled it. Neither was wired
  into onboarding, `SOUL.md.template`, config templates, or any eval/harness
  check — nothing in the onboarding SOP actually collects the SMTP
  credentials himalaya would need, so the capability was effectively
  unreachable in practice while still adding a Rust toolchain build stage
  and two extra installs to every tenant image. A tenant that genuinely
  needs either capability can still get it through the existing runtime
  lazy-install mechanism (`/opt/data/lazy-packages`, see
  `docs/architecture.md`'s "Tenant Plugin Persistence" section) — the same
  path already used for every other tenant-specific or occasional-use
  package — rather than paying the build cost for every tenant regardless
  of whether they use it.
- **`README.md`'s "Before You Begin" table — removed the "Email details
  (optional)" row.** It described SMTP host/port/username/password as
  something to have ready for onboarding, but no onboarding step ever
  actually asked for or used these fields; the row only ever existed because
  `himalaya` was in the image. Removed rather than left as dead
  documentation now that the capability itself is gone.
- **`docs/architecture.md`'s "What is never in the manifest" note** — updated
  its example of image-baked packages (previously `faster-whisper`,
  `himalaya`) to the packages actually still baked in (`mnemosyne-memory`,
  `mnemosyne-hermes`), with a pointer to this removal for anyone who goes
  looking for the old examples.

## 0.16.15 - 2026-07-05

### Fixed

- **`platform/tenant-hermes/scripts/tenant-entrypoint.sh` — a prior incident's
  remediation notes claimed `exec gateway run` needed
  `. venv/bin/activate` first, but no corresponding fix was ever committed to
  this template, and the claim was never reconciled against the base image's
  own `ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"`
  (nousresearch/hermes-agent Dockerfile), which already puts the venv on PATH
  for every process in the container regardless of this script's `command:`
  override. That mismatch was flagged in an audit as needing verification
  rather than being assumed fixed. Rather than re-adding an unverified
  `source venv/bin/activate` unconditionally (which may have been masking a
  different root cause, e.g. a stale image layer), the script now checks
  whether `gateway` actually resolves on PATH first and only falls back to
  venv activation, then to `hermes gateway run` directly, if it doesn't —
  each fallback logs clearly so a real base-image PATH regression is a loud,
  reportable signal instead of a silent workaround.

## 0.16.14 - 2026-07-05

### Fixed

- **`platform/scripts/run-business-research-subagent.py` (onboard-tenant step 1.15)
  called `api.anthropic.com` directly with a bare `ANTHROPIC_API_KEY` read from
  the host's OS environment.** Nothing in `setup-platform.sh`,
  `setup-prerequisites.sh`, or `setup-admin-hermes.md` actually provisions that
  variable, and it was never the same credential as the admin or tenant
  agents' own provider — every provider key in this platform's `.env` files is
  the placeholder `routed-via-agent-vault`; the real key lives only in Agent
  Vault and is injected at the network layer. In practice the sub-agent failed
  on every onboarding unless someone had separately, manually exported a real
  Anthropic key on the host, and silently fell back to cold generation as
  designed — masking the failure as "sub-agent unavailable" rather than a
  fixable misconfiguration. `research-tenant-business.md`'s own description
  ("or the platform's configured LLM key") already implied this should have
  worked; the code never actually implemented that fallback.
  Fixed by dropping the direct API call and instead shelling out to
  `hermes -z` from the admin Hermes install (`/opt/aaas/platform/admin`) — the
  same one-shot mechanism already used for proxy probes
  (`setup-admin-hermes.md` Step 7, `manage-agent-vault.md`,
  `handle-watchdog-alert.md`) and tenant evals (`eval-runner.sh`). This
  inherits the admin agent's actual configured provider/model and its
  already-provisioned Agent Vault routing (`HTTP_PROXY`/`HTTPS_PROXY`,
  `AGENT_VAULT_TOKEN`, `SSL_CERT_FILE` from `platform/admin/.env`) with no
  second credential required. Also added a bounded proxy pre-check (mirroring
  Step 7) before the `hermes -z` call, since it has no internal timeout and a
  broken proxy path previously would have hung indefinitely rather than
  failing fast. `docs/architecture.md`, `research-tenant-business.md`, and
  `onboard-tenant.md`'s truncation-handling notes updated to match — the
  `SUBAGENT_MAX_TOKENS`/`stop_reason`-based truncation check no longer applies
  since generation now runs through the admin agent's own model settings; the
  script instead flags likely-truncated JSON heuristically.

## 0.16.13 - 2026-07-05

### Added

- **`platform/reference/llm-provider-catalog.md` — new shared LLM provider
  catalog.** Single source of truth for provider hostnames and API key env
  var names, replacing the hardcoded 5-row table duplicated across
  `setup-admin-hermes.md`, `manage-agent-vault.md`, `provision-tenant-vault.md`,
  and `docs/architecture.md`. Adds `opencode-go` (previously unsupported —
  no env var, hostname, or table entry existed anywhere) plus a dozen other
  common providers, a deterministic env-var derivation rule, and an
  exceptions list for OAuth-only and multi-credential providers that must be
  escalated to the operator rather than auto-configured. Custom/arbitrary
  `base_url` endpoints remain explicitly out of scope. Wired into
  `scripts/setup-platform.sh`: added to `MANAGED_ASSET_RELATIVE_PATHS` (so
  `mkdir`/`copy_tree`/backup all pick it up automatically).
- **`scripts/setup-platform.sh`'s `validate_install()` now derives its
  required-file list from `MANAGED_ASSET_RELATIVE_PATHS`** instead of
  keeping its own separate hardcoded `required=()` array. This was the one
  place that still hadn't been folded into the single-source-of-truth
  cleanup described in the array's own top-of-file comment — confirmed via
  a byte-for-byte diff that the derived list matches the old hardcoded one
  exactly, so this is a drift-proofing fix with no behavior change today,
  but means any future managed asset only needs to be added in one place
  going forward.

### Changed

- **Operators/tenants are no longer asked for the API key env var name
  during onboarding.** `onboard-tenant.md` step 1 and `setup-admin-hermes.md`
  now derive it from the provider ID via the new catalog instead of
  collecting it as a question — e.g. `opencode-zen/big-pickle` or
  `provider = openrouter, model = openai/gpt-oss-120b` is now enough input on
  its own. Only genuinely unlisted or excepted providers still prompt a
  follow-up question, and never for the env var name itself.

### Fixed

- **`platform/tenant-hermes/env.template`, `platform/scripts/provision-tenant-vault.sh`,
  and `docs/architecture.md` still used `OPENCODE_API_KEY`** instead of
  `OPENCODE_ZEN_API_KEY` — the same drift already fixed on the admin side
  (see the 0.x entry below), left unfixed on the tenant side. All three now
  match the catalog; `OPENCODE_GO_API_KEY` added alongside.
- **`setup-admin-hermes.md`'s post-setup verification grep hardcoded "one of
  the five Step 5.2 names"** as an allow-list for `*_API_KEY` variables in
  `admin/.env`. This silently failed closed for any catalog provider beyond
  the original five (including the newly-added `opencode-go`). The check now
  derives its allow-list from the catalog file at check time instead of a
  hardcoded pattern.

- **`platform/scripts/aaas-watchdog.sh` — watchdog falsely escalated admin-hermes when it was never installed.**
  `admin-hermes` was spliced into the monitored entity list unconditionally,
  with no check for whether it had actually been installed
  (`setup-admin-hermes.md`). On a fresh platform without admin Hermes set up,
  every cycle probed unreachable ports 9119/8642, failed the restart attempt
  (already guarded on a missing `admin/.env`), waited out the full
  `ADMIN_HERMES_PROBE_TIMEOUT` × `MAX_RESTART_ATTEMPTS`, and escalated to
  OpenCode — purely because admin Hermes hadn't been installed yet, not
  because anything was broken. admin-hermes is now only added to the
  monitored entity list when `admin/.env` exists.

## 0.16.12 - 2026-07-05

### Added

- **`docs/troubleshooting.md` — new entry for Docker Desktop + WSL2
  nftables gap on custom bridge networks.** Documented, not automated: on
  Docker Desktop for WSL2 specifically (not a plain Ubuntu host), a custom
  bridge network like `agent-vault-net` can be missing the `DOCKER-FORWARD`
  and `DOCKER-CT` nftables rules the default `docker0` bridge gets
  automatically, causing full internet loss for that container (LLM calls
  through the Agent Vault proxy fail with a `502` after a ~12s timeout).
  Includes a quick diagnostic (`nft list chain ... | grep <bridge-iface>`)
  and the live workaround (`nft add rule ...`). Cross-referenced from
  `setup-agent-vault.md`'s Notes section. This is not wired into any setup
  script — no WSL2 detection exists yet — it's a reference to cut
  troubleshooting time if a WSL2 host hits it, called out as not applicable
  on native Ubuntu installs.
- **`setup-admin-hermes.md` Step 7 — fast bounded pre-check before
  `hermes -z`.** `hermes -z "..."` has no timeout and produces no output
  while stuck, so a failing proxy path presents as an indefinite hang
  rather than a diagnosable error. Added an optional `curl --max-time 10
  --proxy ...` check against the operator's configured provider hostname
  to run first if `hermes -z` hangs — it fails fast with an actual error
  (connection refused, timeout, or a real HTTP response) instead of
  requiring the operator to wait out and then manually trace the proxy
  chain from scratch. Does not replace the existing `hermes -z` check.

## 0.16.11 - 2026-07-05

### Fixed

- **`setup-admin-hermes.md` Step 1 — `HERMES_HOME` was never exported to
  the operator's shell profile, so the interactive `hermes` CLI silently
  used the wrong config.** The skill only ever set `HERMES_HOME` inline for
  one-off commands (the Mnemosyne plugin install) or via the systemd unit's
  `EnvironmentFile=` (Step 7) — never persisted it to `~/.bashrc` the way
  Step 1 already does for `PATH`. Running `hermes` from an interactive
  login shell has no `HERMES_HOME` set, so it falls back to
  `~/.hermes/config.yaml` — the official installer's own default profile
  and default model — instead of `/opt/aaas/platform/admin/config.yaml`
  and the provider/model actually configured for this platform. No error;
  it just silently runs the wrong model, wrong skills, wrong sessions
  directory. (This is the same fallback documented in Step 3.1 item 4 for
  the gateway process, just hit here via bare CLI use instead of a
  manual/nohup start.) Step 1 now exports `HERMES_HOME` to `~/.bashrc`
  right after the existing `PATH` export, using the same
  grep-before-append pattern.

## 0.16.10 - 2026-07-05

### Fixed

- **`platform/scripts/aaas-watchdog.sh` — `%U` does not resolve to `User=`'s
  UID in a system unit.** The generated `aaas-watchdog.service` is a
  *system* unit (installed to `/etc/systemd/system`, run via `sudo
  aaas-watchdog.sh --install`), not a `--user` unit. Its
  `Environment=XDG_RUNTIME_DIR=/run/user/%U` comment claimed `%U` resolves
  to the UID of the unit's own `User=` directive "for a system unit, not
  just user units" — that's backwards. In a system unit, `%U`/`%u`
  specifiers resolve to the system manager's own UID (0, since this unit
  runs as root via sudo), regardless of `User=`. Confirmed live: with
  `User=aaas` (UID 1000), `XDG_RUNTIME_DIR` still expanded to `/run/user/0`.
  That pointed `systemctl --user` (used by `admin_hermes_restart()`) at a
  session bus that doesn't exist, silently falling through to the `nohup`
  fallback — which then killed the correctly-running systemd-managed admin
  Hermes process via `pkill -f 'hermes.*dashboard'`. `--install` now
  resolves the operator's UID itself via `id -u` at install time and bakes
  the literal value into `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`
  instead of relying on `%U`. The misleading comment is removed.

- **`platform/admin-hermes/env.template` and `setup-admin-hermes.md` Step
  5.5 — default `NO_PROXY` was missing every non-LLM host admin Hermes
  talks to.** The Agent Vault MITM proxy on `localhost:14322` is scoped to
  LLM API calls only; it has no route for Telegram's Bot API or
  HuggingFace model downloads. With `NO_PROXY=localhost,127.0.0.1` as the
  only exclusion, both `api.telegram.org` (Telegram gateway connectivity,
  configured in Step 3.1) and `huggingface.co` (Mnemosyne embedding model
  downloads) were routed through the LLM-only proxy and failed with a `502
  Bad Gateway` instead of connecting directly. Default `NO_PROXY` in both
  files now includes `api.telegram.org,telegram.org,*.telegram.org,
  huggingface.co` alongside `localhost,127.0.0.1`.

## 0.16.9 - 2026-07-05

### Fixed

- **The `.raw` truncation sidecar (added in 0.16.8) was a diagnostic
  artifact nobody actually read.** It sat in host `/tmp` (not a container —
  the admin agent and its scripts run on the host, only tenant-hermes runs
  inside per-tenant containers), contained real interview/research content,
  and had no cleanup path beyond the general `/tmp` file — step 19's cleanup
  only ever targeted the main output file, never the `.raw` sidecar.
  `onboard-tenant.md` step 1.15 now reads the `.raw` file immediately when a
  truncation is detected, notes how far generation got in the task report,
  and deletes the file in the same step — a same-run diagnostic read, not
  something left on the host afterward. Step 19's cleanup now also removes
  `.raw` as a safety net in case the truncation branch was somehow skipped.

## 0.16.8 - 2026-07-05

### Fixed

- **The business intelligence sub-agent (`run-business-research-subagent.py`)
  had four effectiveness/efficiency gaps, all still silent failure modes:**
  - Raised default `SUBAGENT_MAX_TOKENS` from 2048 to 3072 — the requested
    output (three vault notes plus three arrays) could run to ~1500-1800
    tokens of content before JSON overhead, tight enough to risk silent
    truncation that looked identical to any other JSON-parse failure.
  - Added an explicit truncation check against the API's own `stop_reason`;
    a `max_tokens` cutoff now fails with a distinct, named error (and saves
    the partial text to `{output-file}.raw`) instead of surfacing as a
    generic "not valid JSON" failure with no pointer to the actual cause.
  - Added one retry with a short backoff for 429 (rate limit) and network
    errors only — onboarding is a one-shot event with no automatic re-run,
    so a single transient error used to permanently cost the tenant the
    richer generation. Non-retryable errors (401/400) still fail immediately.
  - Extended `validate_output()` with array-length checks
    (`vertical_capabilities_block` 4-6 items, etc.) and a check for output
    that echoes the schema's own instruction text back as content instead of
    following it — both previously invisible to validation, which only
    checked that keys existed.

### Added

- **No documented way to re-run the sub-agent for an already-onboarded
  tenant.** `research-tenant-business.md` now documents a re-run path for
  when an operator provides a website URL after onboarding: re-run the
  script standalone, then apply only the existing write steps (SOUL/MEMORY
  substitution, business-data append, vault seeding) rather than repeating
  onboarding. Reuses all existing code; no new tooling.

## 0.16.7 - 2026-07-05

### Fixed

- **`harness/check-tenant.sh` could not tell a properly locked-down Agent Vault
  sidecar apart from a dead one.** `agent_vault_mgmt_port_not_reachable_from_tenant`
  and `agent_vault_sidecar_mgmt_port_not_reachable` both record `PASS` on any
  failed connection — which is exactly what a crashed
  `agent-vault-proxy-{tenant-id}` container looks like from inside the tenant,
  same as a properly-isolated one. Both checks could pass while the sidecar
  was down and the tenant's LLM calls were actually failing. Added
  `agent_vault_sidecar_running` (docker ps check on the sidecar container
  itself) and `agent_vault_sidecar_proxy_port_reachable` (a positive check
  that :14322 actually responds) so sidecar liveness is proven directly
  instead of inferred from the absence of a connection. The comment claiming
  ":14322... is checked separately" was previously false — no such check
  existed anywhere in the file.

### Removed

- **The "local SOP override" tier of `improve-sop.md` never had a loader.**
  The SOP documented writing an "active" override to
  `platform/local/sop/{sop-name}.md`, but no code anywhere in the platform
  ever reads that directory — the SOP's own text said as much
  ("If the platform does not yet load local overrides automatically, write a
  proposal instead"). This left a permanently-unreachable code path
  documented as a real workflow option. Removed the local-override concept
  entirely from `improve-sop.md`, `docs/architecture.md`, and `README.md`.
  SOP improvements now go through the proposal path only
  (`reports/sop-improvements/`); an operator who wants a change applied
  immediately gets it patched into the native SOP directly, with their
  explicit confirmation, rather than into an unreviewed parallel file.

## 0.16.6 - 2026-07-04

### Fixed

- **`docs/architecture.md` had no section on tenant plugin persistence, and four
  places in the codebase (`tenant-install.sh`, `harness/check-tenant.sh`,
  `docker/Dockerfile` twice) pointed to `tenant-plugin-persistence-issue.md` as
  "the" explanation for the mechanism — a file that does not exist anywhere in
  the repository.** Added a real "Tenant Plugin Persistence" section to
  `docs/architecture.md` covering how `tenant-install.sh`/`reconcile-plugins.sh`
  work, the `remove`/`list`/`installed_paths` behavior added in 0.16.4, the
  lifecycle-ownership split added in 0.16.5 (tenant decides what to
  install/remove, admin owns the mechanism and troubleshoots but doesn't act
  unilaterally), and an explicit note that image-baked packages (`faster-whisper`,
  `himalaya`) are correctly never tracked in `installed-plugins.yaml`. Redirected
  all four dangling references to this new section instead of introducing a
  second doc to maintain.

## 0.16.5 - 2026-07-04

### Added

- **Plugin lifecycle ownership was undocumented.** `tenant-install.sh remove`/`list`
  (added in 0.16.4) had no attached policy for who should use them or when, on either
  side:
  - `SOUL.md.template` now tells the tenant agent to `remove` a package it installed
    once it knows the package is no longer needed (superseded, or the skill that
    required it was abandoned), and states plainly that nobody else reviews this —
    the tenant agent is the only one with the context to know whether something it
    installed is still in use.
  - `monitor-health.md` gets a new opportunistic, explicitly non-blocking step
    (8.5) where the admin agent may glance at `tenant-install.sh list` output for a
    flagged tenant and note anything unusually large or stale in the report — but
    is told not to run `remove` itself, since it lacks the tenant-side context to
    know if something is still backing a scheduled skill. Deliberately not added
    to `checklists/monitor-health.required.json`, so it never becomes a completion
    gate, matching the existing opportunistic-review pattern already used for
    self-written skill provenance review in `PLATFORM-REFERENCE.md`.

## 0.16.4 - 2026-07-04

### Fixed

- **`tenant-install.sh` had no way to uninstall a tenant-installed plugin.**
  The script only ever supported `pip`/`binary` install, and `record_manifest`
  only appended to `installed-plugins.yaml` — there was no `remove` or `list`
  subcommand, so a broken or unwanted plugin required manual, off-script
  filesystem and manifest edits with no documented procedure (`troubleshoot-tenant.md`
  had no removal guidance either). Added `tenant-install.sh remove <name>` and
  `tenant-install.sh list`. Because `pip`/`uv` have no supported way to uninstall a
  single package from a shared `--target` install, pip installs now snapshot the
  target directory before/after install and record exactly which top-level
  entries that install added (`installed_paths` in the manifest), so `remove`
  can delete precisely one package's files without touching any other package
  installed into the same directory. Plugins installed by a pre-`installed_paths`
  `tenant-install.sh` are refused by `remove` with a manual-cleanup message
  rather than risking a shared-directory wipe. `troubleshoot-tenant.md` and
  `PLATFORM-REFERENCE.md` updated to document and recommend `remove`/`list`.

- **`tenant-install.sh` validated manifest metadata only after the install/download
  had already run.** The double-quote/newline check on `name`/`target`/`reason`
  lived inside `record_manifest`, called after `uv pip install` or `curl` had
  already succeeded. A rejected name or reason left the package or binary live
  on disk with no manifest entry — an installed-but-untracked artifact that
  `reconcile-plugins.sh` doesn't know about, and that `troubleshoot-tenant.md`'s
  "not listed means never installed through this script" guidance would then
  describe incorrectly. The same check now runs before the install/download
  step in both the `pip` and `binary` branches.

- **`tenant-install.sh` created duplicate manifest entries when reinstalling the
  same package or binary name.** `record_manifest` only ever appended a new
  YAML block; installing the same name twice left two blocks in
  `installed-plugins.yaml`, both processed redundantly by `reconcile-plugins.sh`
  on every container start. `record_manifest` now drops any existing block for
  the same name before appending the new one.

## 0.16.3 - 2026-07-04

### Fixed

- **`skill-verify.sh` tilde-path sentinel not surfaced distinctly by callers.**
  The 0.16.2 fix returned an `ERROR:unresolvable-tilde-path:...` sentinel from
  `path_pattern()` but neither `check_file_exists_at`, `check_file_does_not_exist_at`,
  nor `check_content_includes` inspected it — the sentinel fell through to ordinary
  FAIL paths, making a bad `~/` spec in a skill file indistinguishable in output from
  a genuinely missing file. All three callers now detect the sentinel and emit a
  descriptive FAIL naming the unsupported path form and the correct alternative.

## 0.16.2 - 2026-07-04

### Fixed

- **`skill-verify.sh` tilde path-handling matched too broadly.** The `~/*` case arm
  stripped only the `~/files/` prefix, so any path beginning with `~/` but not
  `~/files/` (e.g. `~/vault/note.md`) had the tilde left in place and resolved to
  a bogus `$FILES_DIR/~/vault/...` path with no error. Narrowed the matching arm to
  `~/files/*` only; added an explicit error arm for any other `~/` path so failures
  surface clearly instead of silently.

- **`aaas-watchdog.sh` had an unused `REPORT_DIR` variable** (shellcheck SC2034).
  Reports are written by the admin agent (via `write-report.md`) after the watchdog
  hands off to OpenCode — the watchdog itself never writes to `reports/`. Removed.

- **`preflight-check.sh` had a redundant `PLATFORM_ROOT="$PLATFORM_ROOT"` env-prefix**
  on the `check-admin-drift.sh` invocation (shellcheck SC2097/SC2098). The path used
  to locate the script is already expanded from the parent shell's `$PLATFORM_ROOT`
  before the fork; the prefix was a no-op. Removed.

## 0.16.1 - 2026-07-04

### Fixed

- **`skill-verify.sh` credential scan was silently a no-op inside the tenant container.**
  The default `PRIMITIVES_FILE` path pointed to a host-only location never mounted
  into any tenant container, so `run_credential_scan()` always read a missing file
  and passed every skill unconditionally. Fixed on two fronts: (1) default path
  changed to `/opt/data/evals/_skill-verification-primitives-v1.yaml` (container-local);
  (2) `install-tenant-scripts.sh` now copies `_skill-verification-primitives-v1.yaml`
  from `tenant-hermes/evals/` into `{tenant-dir}/evals/` during onboarding and
  upgrades, so the file is actually there. A missing-file guard now fails loudly
  with a descriptive error rather than silently passing.

- **`upgrade-tenants.md` falsely claimed `upgrade-tenant.sh` re-renders `SOUL.md` policy blocks.**
  The script has no SOUL.md logic. Corrected the SOP: step 3 description no longer
  makes this claim; new step 3.1 makes the admin-agent SOUL.md re-render explicit
  and documents when a manual `--force-recreate` is needed if it was the only change.

- **`provision-tenant-vault.md` step 9 told operators to expect `agent-vault` on the tenant network.**
  Agent Vault never joins a tenant network — only the forwarding sidecar does.
  Comment corrected to `agent-vault-proxy-{tenant-id}`.

- **`manage-agent-vault.md` listed `OPENCODE_API_KEY` for OpenCode Zen** instead of
  `OPENCODE_ZEN_API_KEY` (the name used by `setup-admin-hermes.md`, `env.template`,
  and the allowlist grep). An agent rotating this key would register it under the
  wrong name, causing silent proxy injection failure.

- **`PLATFORM-REFERENCE.md` chmod rule conflicted with `repair-tenant-ownership.sh`.**
  The doc prescribed specific non-recursive `chmod 755`/`chmod 644` on two paths;
  the script (correctly) does recursive `chmod -R go+rX`. Doc updated to match the
  script and explain why recursive is required.

- **`PLATFORM-REFERENCE.md` "Gateway command: gateway run" was stale** — the
  container command has been `tenant-entrypoint.sh` since plugin persistence was
  added. Updated to reflect the actual compose `command:`.

- **`handle-watchdog-alert.md` was not tracked as a managed asset.** Added to
  `MANAGED_ASSET_RELATIVE_PATHS`, `validate_install()` required[], and the General
  Skills index in `PLATFORM-REFERENCE.md`.

- **`_skill-verification-primitives-v1.yaml` was not in `MANAGED_ASSET_RELATIVE_PATHS`.**
  Added alongside `_fixed-safety-v1.yaml`. Also added to `validate_install()` required[].

- **`validate_install()` required[] was missing 10 files present in `MANAGED_ASSET_RELATIVE_PATHS`.**
  Added: `policy/platform-policy.yaml`, `scripts/aaas-watchdog.sh`,
  `scripts/generate-platform-eval.sh`, `scripts/validate-platform-rules.sh`,
  `scripts/run-business-research-subagent.py`, `incidents/hermes-admin-failure.md`,
  `skills/handle-tenant-request.md`, `skills/manage-agent-vault.md`,
  `skills/research-tenant-business.md`, `tenant-hermes/scripts/seed-vault-context.py`.

- **`setup-agent-vault.md` / `setup-admin-hermes.md` had ambiguous watchdog install ownership.**
  `setup-agent-vault.md` step 6 is now the unconditional canonical install point.
  `setup-admin-hermes.md` step 8 is now a confirm-active step with a fallback install
  only for hosts that skipped agent vault setup.

- **`research-tenant-business.md` was absent from PLATFORM-REFERENCE.md General Skills index.**
  Added alongside `handle-watchdog-alert.md`.

- **`setup-platform.sh` did not `chmod +x` `seed-mnemosyne.py`** (the other two `.py`
  scripts already had it). Added.

- **Dockerfile had a stale `# [ERROR]` comment** left over from a `validate_install()`
  error message template. Changed to a `# NOTE:` comment.

## 0.16.0 - 2026-07-04

### Added

- **Business intelligence sub-agent for onboarding (`onboard-tenant.md` step 1.15).**
  Inserts a focused Claude API call between web research (step 1.1) and block
  generation (step 1.2). The sub-agent synthesises the operator interview answers
  and web research text into four structured artifacts — richer capability and
  brand fact blocks, a business context section for `business-data.md`, and three
  pre-written vault seed notes — replacing the cold LLM generation that previously
  produced shallow, generic output.

  The core problem being solved: the operator interview collected 15+ structured
  fields, and web research gathered raw text, but both were discarded after
  producing a thin 3–6 line capabilities block and 1–4 brand fact lines. The
  tenant agent then started with minimal context, unable to sound like it knew the
  business without months of runtime learning.

  **`platform/skills/research-tenant-business.md`** (new) — skill doc defining the
  sub-agent's contract: inputs, invocation pattern, output field mapping to
  downstream SOP steps, fallback handling, confidence levels, and cleanup.

  **`platform/scripts/run-business-research-subagent.py`** (new) — host-side Python
  script that assembles the prompt from a stdin JSON context block, calls
  `claude-sonnet-4-6` via the Anthropic API, validates the response shape, and
  writes clean JSON to a temp file. Handles markdown fence stripping, saves a
  `.raw` sidecar on parse failure, stamps `_meta` for traceability, and exits
  non-zero on any failure so the SOP fallback path triggers cleanly.

  **`platform/tenant-hermes/scripts/seed-vault-context.py`** (new) — reads the
  sub-agent JSON output and writes three vault seed notes (`Reference/Business
  Overview.md`, `Reference/Vertical Playbook.md`, `Recurring/Patterns to Watch.md`)
  into the scaffolded vault. Idempotent: skips files that already exist.
  Runs on the host against the mounted volume — no container exec required.
  Follows the same PASS/SKIP/FAIL + exit-code conventions as `seed-mnemosyne.py`.

- **`onboard-tenant.md` updated** to integrate the sub-agent into the onboarding
  flow with four targeted edits:
  - Step 1.15 (new): assembles context block, invokes the sub-agent script,
    extracts output fields, surfaces confidence to the operator, defines fallback
    behaviour.
  - Step 1.2 updated: prefers sub-agent `vertical_capabilities_block` and
    `vertical_brand_facts_block` over cold generation; falls back only when
    unavailable.
  - Step 4.1 updated: `business-data.md` now has two sections — the existing
    operational details section, plus a new "Assistant Context" section populated
    from the sub-agent's `business_data_context_section` array (insider knowledge
    lines that help the agent sound like it knows the business without being asked).
  - Step 4.2 updated: after vault scaffolding, calls `seed-vault-context.py` to
    write the sub-agent's three Reference and Recurring notes into the vault.
    Sub-agent unavailability skips the seed step without aborting onboarding.
  - Step 6.2 updated: `install-tenant-scripts.sh` description now lists
    `seed-vault-context.py`.
  - Step 13 note updated: clarifies vault now starts pre-populated when sub-agent
    succeeded, rather than empty.
  - Step 19 updated: report now covers sub-agent status, confidence, vault seed
    notes written, and temp file cleanup (`rm -f /tmp/aaas-research-{tenant-id}.json`).

- **`platform/scripts/install-tenant-scripts.sh` updated** — `seed-vault-context.py`
  added to the install list (header comment and `install_script` call), so it is
  deployed into `/opt/aaas/tenants/{tenant-id}/scripts/` alongside the other
  tenant runtime scripts during onboarding and upgrades.

- **`scripts/setup-platform.sh` updated** — three new managed assets registered in
  `MANAGED_ASSET_RELATIVE_PATHS` (`skills/research-tenant-business.md`,
  `scripts/run-business-research-subagent.py`,
  `tenant-hermes/scripts/seed-vault-context.py`) and corresponding `chmod +x`
  calls added to the install block.

## 0.15.10 - 2026-07-03

### Fixed

- **`scripts/setup.sh` — fresh installs unconditionally forced `--build-image`, and explicitly passing `--build-image` on a fresh install was silently accepted then failed late.**
  Two related problems in `setup.sh`:
  1. `BUILD_IMAGE=true` was set automatically whenever `MODE=fresh`, causing
     every fresh install to attempt a Docker build before Agent Vault had
     been started. The auto-set has been removed; fresh installs now skip the
     image build by default.
  2. Explicitly passing `--build-image` on a fresh install (e.g.
     `bash <(curl …/setup.sh) --build-image`) was accepted without complaint,
     then failed after running the entire prerequisite bootstrap (which can
     take several minutes). Added an early rejection immediately after mode
     detection — before any prerequisites run — that prints a clear error
     explaining why `--build-image` is not valid on a fresh install and what
     to do instead. Updated `usage()` to document the same constraint.
  In both cases the underlying reason is the same: building the tenant image
  requires `agent-vault-ca.pem`, which can only be fetched from Agent Vault
  after it has been started and set up (setup-agent-vault SOP step 3), which
  cannot happen until after the fresh install completes.

- **`scripts/setup-platform.sh` — `build_image()` did not check for `agent-vault-ca.pem` before calling `docker build`.**
  Added an explicit pre-build guard: if `agent-vault-ca.pem` is absent,
  `build_image()` now exits with a clear message naming the exact `curl`
  command needed (setup-agent-vault SOP step 3) rather than letting Docker
  emit the cryptic `"/agent-vault-ca.pem": not found` COPY checksum error.
  `validate_install()` already warned about the missing file; this closes
  the same gap specifically in the build path.

- **`platform/sop/build-image.md` — no pre-build CA certificate check.**
  Added step 3 requiring operators to verify `agent-vault-ca.pem` is present
  (and fetch it if not) before running `docker build`. Step numbers from the
  old step 3 onward shifted by one.

## 0.15.9 - 2026-07-03

### Fixed

- **`platform/scripts/aaas-watchdog.sh` — fresh install errored with `[ERROR] Watchdog escalation prompt must explicitly forbid recreate/stop/rm commands in unattended sessions`.**
  `validate_install()` greps for `"must never run"` in `aaas-watchdog.sh`. The
  escalation prompt already said `"never recreate, stop, or remove any container for any reason"`
  but not the literal phrase `"must never run"`. Added an explicit sentence
  `"Unattended sessions must never run recreate, stop, or remove commands on any container."`
  to the prompt so the validator passes and the constraint is clearer to the agent.

- **`platform/sop/onboard-tenant.md` — four `validate_install()` checks that were always failing on a fresh install (found by sweep of all checks).**
  All four were caused by SOP refactors that replaced inline prose/YAML with
  script delegations without updating the validator strings:
  - `vault-init-tenant.sh`: step 4.2 was refactored to call `backfill-tenant-vault.sh`
    without mentioning that it calls `vault-init-tenant.sh` internally. Added the
    reference.
  - `restart: unless-stopped` and `mem_limit: 1g`: step 8 was refactored to delegate
    to `add-tenant-compose-service.sh`, removing the inline YAML that contained
    these strings. Added them explicitly to the script description.
  - `mnemosyne store`: the seeding step was refactored to use `seed-mnemosyne.py`
    (no longer calling `hermes mnemosyne store` directly), losing the string the
    validator expected. Added a sentence pointing to `hermes mnemosyne store` as
    the underlying per-fact command for manual use.

## 0.15.8 - 2026-07-03

### Fixed

- **`platform/sop/upgrade-tenants.md` — fresh install errored with `[ERROR] Upgrade tenants SOP must repair tenant volume ownership after edits`.**
  The `validate_install()` check in `setup-platform.sh` greps for the string
  `repair-tenant-ownership.sh` in `upgrade-tenants.md`. Since 0.15.4 the SOP
  delegates all per-tenant sub-steps (including ownership repair) to
  `upgrade-tenant.sh`, which calls `repair-tenant-ownership.sh` internally, but
  the SOP prose only said "ownership repair" without naming the script. The
  grep therefore always failed on a fresh install, printing an ERROR and
  aborting setup. The step 3 description now explicitly names
  `repair-tenant-ownership.sh` so the validator passes.

## 0.15.7 - 2026-07-03

### Fixed

- **`scripts/setup-platform.sh` — validator checks for `update-tenant.md` and `upgrade-tenants.md` ownership repair were broken since 0.15.4.**
  In 0.15.4 both SOPs were refactored to call `repair-tenant-ownership.sh`
  instead of running `sudo chown -R 10000:10000` inline. The two validator
  `grep` checks in `validate_install()` were not updated at the same time and
  kept looking for the raw `chown` string, causing `[ERROR] Update tenant SOP
  must repair tenant volume ownership after edits` on every install. The checks
  now look for `repair-tenant-ownership.sh`, which is the canonical ownership
  repair entry point in both SOPs. The `onboard-tenant.md` check is unchanged
  (that SOP still references the raw `chown` string in its inline comment).



### Fixed

- **`scripts/setup-platform.sh` — same-version re-run no longer pauses for interactive input.**
  `decide_install_strategy` previously called `prompt_confirm_install` when the
  installed and repo versions were equal, which blocks on `/dev/tty`. This caused
  a hang whenever setup was re-run after a partial failure, a clean re-run of the
  same version, or any `curl | bash` / `bash <(curl ...)` invocation without
  `--yes`. The `equal` case now auto-selects "continue with backup" without
  prompting — this is always the correct behavior (idempotent, safe, no data
  loss). The interactive prompt is now only shown for genuine downgrades
  (installed version newer than repo version), where operator confirmation
  is legitimately required.



### Fixed

- **`scripts/setup-prerequisites.sh` — `sg` not found on minimal Ubuntu images; docker group re-exec now uses `sudo -g docker` instead.**
  `sg` is part of `shadow-utils` and is absent on many Ubuntu cloud/minimal
  configurations. The 0.15.4 re-exec used `exec sg docker -c "..."`, which
  caused the script to exit immediately with `sg: not found` on affected
  machines, forcing the user to re-run setup manually. The re-exec now uses
  `exec sudo -E -u "$USER" -g docker bash "$0" "$@"` as the primary method
  (`sudo` is always present on Ubuntu), with `sg` retained as a secondary
  fallback. If neither is available a clear warning is printed and the script
  continues, asking the user to log out/in if Docker commands subsequently fail.

- **`scripts/setup-platform.sh` — misleading "Start Docker" error when Docker is running but the group is not yet active in the shell.**
  When a user re-runs `setup.sh` after a failed prerequisites run (e.g. after
  the `sg: not found` failure above), `setup.sh` auto-detects upgrade mode
  (platform dir already exists) and skips the prerequisites step, going straight
  to `setup-platform.sh`. The `docker info` check there failed with
  "Docker Engine is not reachable" even though Docker was running fine — the
  real cause was the docker group not being active in the current shell.
  The check now tries `sudo docker info` as a fallback: if that succeeds it
  warns the user about the group, installs a `docker()` wrapper for the
  remainder of the session so all subsequent docker calls work, and continues.
  Only if `sudo docker info` also fails does it error with a genuinely
  actionable "Start Docker" message.



### Fixed

- **`scripts/setup-platform.sh` — `backup_managed_assets` no longer has a second hand-maintained asset list.**
  The function previously kept its own independent directory list (`AGENTS.md`,
  `admin-hermes/`, `sop/`, `scripts/`, …) separate from `MANAGED_ASSET_RELATIVE_PATHS`.
  Any new managed asset added to `MANAGED_ASSET_RELATIVE_PATHS` but forgotten in
  this secondary list would silently not be backed up before an upgrade — with no
  warning. The function now derives its backup set directly from
  `MANAGED_ASSET_RELATIVE_PATHS` by extracting unique top-level path components,
  so a new managed asset added in one place is automatically backed up without any
  secondary edit. `CHANGELOG.md` (copied from repo root, not listed in
  `MANAGED_ASSET_RELATIVE_PATHS`) continues to be backed up explicitly.

- **`curl | bash` pipe cannot propagate PATH or group changes back to the calling shell.**
  When the installer is run as `curl ... | bash`, the script executes in a
  subshell whose environment is discarded on exit — `export PATH=...` and group
  membership gained via the docker `sg` re-exec (fixed in 0.15.4) cannot reach
  the user's parent terminal. The "next steps" instructions then immediately say
  `opencode`, which would fail with "command not found" after a piped run.
  Fixed by: (a) updating README and `setup-prerequisites.sh` to recommend
  `bash <(curl ...)` (process substitution — runs in the current shell, not a
  subshell) as the canonical install form; (b) adding an explicit post-run note
  in `setup.sh`'s completion output that explains the pipe limitation and tells
  the user to run `exec bash` if they used the pipe form before invoking opencode.

- **`platform/sop/upgrade-platform.md` — upgrade curl commands missing `--yes`, causing a hard error when the installed version matches the repository version.**
  `prompt_confirm_install` is triggered when the installed and repo versions are
  equal (or the installed is newer). It reads from `/dev/tty` to prompt the
  operator — but `/dev/tty` is not available in a `curl | bash` pipe context,
  so the script exited with an error instead of prompting. The upgrade SOP's
  step 6 and 7 curl commands now include `--yes` (assumes "Continue with backup")
  and carry an explanation of why it is required in this context. The README
  upgrade section is updated identically.



### Fixed

- **`scripts/setup-prerequisites.sh` — Docker group membership now active in the same shell session without logout.**
  `sudo usermod -aG docker $USER` adds the user to the `docker` group, but group
  changes only take effect in a new login session; the current process inherits the
  group list it had at startup and cannot pick up additions via `source ~/.bashrc`
  or `exec bash`. On a fresh install this caused every subsequent Docker command
  in the same `setup.sh` run (`docker info`, `docker pull`, `docker build`,
  `docker compose up`) to fail with a permission-denied on `/var/run/docker.sock`,
  breaking the documented single-command install flow.

  Fix: immediately after `usermod`, the script detects whether the current process
  already has the `docker` group active. If it does not, it re-execs itself under
  the new group via `sg docker -c "..."`, which replaces the process with an
  identical one that carries the refreshed credential set — no logout, no new
  terminal, no manual `newgrp` required. A `DOCKER_GROUP_ALREADY_ACTIVE` guard
  prevents an infinite re-exec loop. When Docker was already installed before
  this run (and the user was already in the group), the re-exec is skipped entirely.

  The closing "next steps" message is updated to accurately describe what is now
  active in the current session (Docker group, nvm, opencode) versus what `exec
  bash` is needed for (new terminals opened later).

### Token optimizations (token-optimization-review.md findings 1–6)

- **`platform/scripts/repair-tenant-ownership.sh`** (new) — extracts the two-command
  `chown -R 10000:10000` + `chmod -R go+rX` ownership repair block that previously
  appeared verbatim in `onboard-tenant.md` (step 7), `update-tenant.md` (step 8),
  `upgrade-tenants.md` (step 3), and `troubleshoot-tenant.md` (Permission Denied
  recovery path), each with ~80–100 tokens of inline prose explaining why both
  commands are required and why `-R` is mandatory. All four call sites now use one
  script call. The prose rationale lives once in the script header as a comment
  (never loaded by the agent). Finding 1.

- **`platform/scripts/backfill-tenant-vault.sh`** (new) — extracts the 5-command
  vault scaffold block (`mkdir -p`, `cp vault-init-tenant.sh`, `chmod +x`, set env,
  run) that previously appeared verbatim in `onboard-tenant.md` (step 4.2),
  `update-tenant.md` (step 7.1), `upgrade-tenants.md` (step 3 vault sub-step), and
  `troubleshoot-tenant.md` (Knowledge Vault Missing path), each with ~60–80 tokens
  of idempotency and downstream-consequence prose. All four call sites now use one
  script call. Takes `{tenant-id}` and `"{business-name}"` as arguments; the
  business name is required to render the vault `README.md` correctly. Finding 2.

- **`platform/scripts/install-tenant-scripts.sh`** (new) — extracts the multi-cp
  and multi-chmod block that previously appeared in `onboard-tenant.md` (steps 6.2,
  6.2.1, 6.2.2) as three separate sub-steps, each with its own prose, and was
  referenced by-name in `upgrade-tenants.md` (requiring the agent to re-load
  onboard-tenant into context to follow the back-reference) and
  `troubleshoot-tenant.md` (plugin recovery path). Installs `skill-verify.sh`,
  `tenant-install.sh`, `reconcile-plugins.sh`, `tenant-entrypoint.sh`, and
  `seed-mnemosyne.py` in one call. Idempotent — files already identical to source
  are skipped. Adding a new runtime script in the future only requires updating
  this one script. All three SOPs now call it by name. Finding 3.

- **`platform/scripts/aaas-watchdog.sh` escalation prompt shortened** — the
  ~200-token inline rule paragraph baked into every unattended escalation prompt
  replaced with a ~50-token reference line: the full Container Recreate Policy
  is enforced by the agent loading `troubleshoot-tenant.md` (named in the prompt),
  so restating it in full was pure duplication. Saves ~150 tokens per escalation
  event. Finding 4.

- **`platform/scripts/provision-tenant-vault.sh`** (new) — extracts all 9
  deterministic steps of `provision-tenant-vault.md` (333 lines) into a single
  script: vault create, isolated network create, forwarding sidecar start and
  connect, primary credential store and service register, optional fallback
  credential and service, agent proxy token mint, `.env` key scrub (primary and
  optional fallback), proxy config injection, `.env` verification, and final
  confirmation prints. `onboard-tenant.md` step 6.3 now calls this script; the
  333-line SOP document is retained as reference documentation but is no longer
  in the agent's execution path. Takes `{tenant-id}`, `{provider-env-var}`,
  `{real-api-key}`, and optional `{fallback-provider-env-var}` +
  `{fallback-real-api-key}`. Exits non-zero on any failure; the `.env` key
  verification is built in. This is the same pattern already applied to
  `add-tenant-compose-service.sh` in 0.15.3, and for the same reason. Finding 5.

- **`platform/scripts/upgrade-tenant.sh`** (new) — extracts the 8-sub-step
  per-tenant inline block from `upgrade-tenants.md` step 3 into a single script.
  The script runs all backfill sub-steps idempotently, tracks `NEEDS_RECREATE`
  internally (no prose reasoning required), performs the image-ID comparison
  correctly (ID vs ID, not tag vs tag), and prints `RECREATED`, `SKIPPED`, or
  `FAIL` per tenant. `upgrade-tenants.md` step 3 is now a single-call loop.
  Directly analogous to `eval-runner.sh`, which already encapsulates the per-tenant
  eval loop in the same pattern. Finding 6.

---

### 0.15.3 - 2026-07-02

### Added
- **`platform/scripts/add-tenant-compose-service.sh`** (new) — deterministic replacement for the prose-described YAML block that `onboard-tenant.md` step 8 previously asked the agent to write by hand into `docker-compose.yaml`. The script appends the complete, correctly indented service block (image, command, restart policy, mounts, env_file, resource limits, network, healthcheck, watchdog labels) and the required `external: true` + `name:` network declaration at the bottom of the file. A duplicate-guard prints `SKIP` if the service is already present rather than appending a second block. `onboard-tenant.md` step 8 now calls this script; the prose bullet list describing each YAML field is removed.
- **`platform/scripts/diagnose-tenant-logs.sh`** (new) — pattern-matches the last N tenant container log lines against the platform's known error vocabulary (permission denied → `chown`/`chmod` repair; Agent Vault proxy auth/SSL/connection failures; Mnemosyne data-dir mismatch or seed failure; iptables/network unreachable; config parse errors; plugin reconcile failures; container stopped/entrypoint error) and prints each finding with its named category and the exact recovery command from `troubleshoot-tenant.md`. Falls back to a `none / no_known_patterns_matched` result for unrecognised output rather than silently passing. `troubleshoot-tenant.md` step 8 now calls this script first; raw `docker logs` is the fallback for unmatched output.

### Fixed
- **`platform/harness/check-tenant.sh` did not verify three compose properties that `add-tenant-compose-service.sh` now guarantees.** The watchdog labels (`aaas.watchdog`, `aaas.watchdog.priority`, `aaas.watchdog.playbook`), the process-based `healthcheck`, and the `external: true` + `name:` network block at the bottom of `docker-compose.yaml` were all required by prose in `onboard-tenant.md` step 8 but never asserted by the harness — meaning a hand-written or partially generated block could silently omit them and still pass all harness checks. Added six new `service_contains`/`contains` checks covering all three properties; they pass against output from `add-tenant-compose-service.sh` by construction.
