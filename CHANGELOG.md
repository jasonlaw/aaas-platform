# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

## 0.10.0 - 2026-06-29

### Added
- **Policy framework: a single canonical source of truth for platform-wide hard rules, plus per-tenant additive restrictions.** New `platform/policy/platform-policy.yaml` holds every platform-wide rule (`no_env_disclosure`, `no_credential_persistence`, `no_credential_in_skills`, `no_network_scan`, `confirm_before_irreversible`, `no_cross_tenant_leakage`, `owner_friendly_language`) as a single `agent_instruction` plus its own `eval_checks`, replacing the previous arrangement where the same rules were duplicated by hand across `SOUL.md.template`'s scattered inline sentences and the separately hand-authored `_fixed-safety-v1.yaml`. Editing a rule now means editing it in exactly one place.
  - **New rule: `no_credential_persistence`.** The tenant agent must never persist a credential, password, API key, connection string, or token anywhere except `/opt/data/.env` — not in a self-written skill, not in Mnemosyne, not in a knowledge vault note, not in a generated/uploaded file. `.env` is written only by the platform operator during onboarding/update; the tenant agent never writes to it itself. This was previously only partially covered by `no_credential_in_skills` (skills only); the new rule covers every persistent tenant-side store.
  - New `platform/scripts/generate-platform-eval.sh` renders `evals/tenant-agent/_fixed-safety-v1.yaml` from `platform-policy.yaml`. **`_fixed-safety-v1.yaml` is no longer hand-edited** — run this script after any `platform-policy.yaml` change, and as part of `upgrade-platform.md`.
  - New `platform/scripts/validate-platform-rules.sh` confirms every `platform-policy.yaml` rule has matching coverage in the generated eval file; run before shipping a platform upgrade.
  - New per-tenant `tenant-policy.yaml` (from `templates/_base/tenant-policy.yaml.template`) holds operator-set, business-specific restrictions in the same rule shape as `platform-policy.yaml`. Additive-only — a tenant rule may narrow but never widen past a platform rule. Empty `rules: []` is the common case.
  - `templates/_base/SOUL.md.template` replaces its scattered inline safety sentences with two rendered marker blocks, `<!-- BEGIN/END PLATFORM RULES -->` and `<!-- BEGIN/END TENANT RULES -->`. `onboard-tenant.md` step 5.1 and `update-tenant.md` step 5.1 render each rule's `agent_instruction` verbatim into the matching block.
  - `harness/check-tenant.sh` and `scripts/validate-tenant-config.sh` check for the marker blocks, `tenant-policy.yaml`'s existence/ownership/`inherits: platform-policy` declaration, and a representative rendered phrase, rather than grepping for the old hand-written sentences.
  - `sop/upgrade-tenants.md` step 3 backfills `tenant-policy.yaml` and re-renders both SOUL.md policy blocks for tenants onboarded before this feature existed.
  - `AGENTS.md` documents the policy directory, the generate/validate scripts, the rendering instruction, and the additive-only constraint on tenant policy.

- **Per-tenant network isolation: every tenant now has its own isolated Docker bridge network instead of sharing `agent-vault-net`.** Previously all tenant containers shared one bridge network with each other and with Agent Vault, meaning a compromised tenant container could potentially reach any other tenant's container. Each tenant now gets `hermes-{tenant-id}-net`, with only that tenant's container and Agent Vault as members.
  - `provision-tenant-vault.md` steps 1a/1b create the network and join Agent Vault to it, before the tenant container starts.
  - `provision-tenant-vault.md` step 5 stops injecting `AGENT_VAULT_ADDR` into tenant `.env` — tenant containers have no legitimate reason to reach Agent Vault's management API (`:14321`), only the proxy port (`:14322`, used implicitly via `HTTP_PROXY`/`HTTPS_PROXY`). `templates/_base/env.template` updated to match.
  - `provision-tenant-vault.md` step 8 and `onboard-tenant.md` step 8 attach the tenant's compose service to `hermes-{tenant-id}-net` (`external: true`) instead of the shared `agent-vault-net`.
  - `deprovision-tenant-vault.md` step 3 disconnects Agent Vault and removes the network during offboarding.
  - `upgrade-tenants.md` step 3 backfills the isolated network (and migrates the compose service onto it) for tenants onboarded before this feature existed.
  - `monitor-health.md` step 5.1 and `harness/check-tenant.sh` verify each active tenant's isolated network exists and, separately, that Agent Vault's management port is actually unreachable from inside that tenant's container — proving isolation, not just network existence.
  - **Note:** Agent Vault's management port (`:14321`) and proxy port (`:14322`) were already bound to `127.0.0.1` on the host in `scripts/setup-platform.sh`'s generated `docker-compose.yaml` — that binding only affects host-to-container access and was never the source of the lateral-movement risk, since containers reach each other directly over a shared bridge network regardless of host port bindings. The per-tenant network change above is the actual fix; no change was needed to the host port bindings.

- **Skill credential scanning: self-written tenant skills are now scanned for embedded credentials before they can be trusted.** New `credential_scan` primitive in `evals/tenant-agent/_skill-verification-primitives-v1.yaml` defines a pattern list (API key prefixes, `password=`/`secret=`/`token=`-style assignments, `user:pass@host` connection strings) sourced from the `no_credential_persistence` and `no_credential_in_skills` platform rules.
  - `scripts/tenant/skill-verify.sh` now runs `run_credential_scan()` unconditionally, immediately after `require_setup`, before evaluating any agent-supplied verification spec. Any match flags the skill (`status: flagged`) and exits non-zero regardless of whether the spec itself would have passed — credential exposure is checked first and independently of what the skill claims to do.
  - `AGENTS.md` documents that this check is automatic and not requested by the tenant agent, and that new patterns are added to the primitives file, not to `skill-verify.sh` itself.

### Changed
- `harness/tenant-harness.yaml.template` and `harness/ACCEPTANCE.md.template` add `policy_rendered` and `network_isolation` as required checks / owner-benefit and platform-check items.
- `README.md` Credential Security Model section documents the policy framework, per-tenant network isolation, and skill credential scanning alongside the existing Agent Vault proxy explanation.

## 0.9.1 - 2026-06-28

### Fixed
- **`provision-tenant-vault` step 5 injected proxy URLs without the vault token, causing 407 from the proxy.** Agent Vault's MITM proxy (port 14322) requires `Proxy-Authorization: Basic base64(token:)` on every `CONNECT` request. The SOP previously wrote `HTTP_PROXY=http://agent-vault:14322` — unauthenticated — so the openai/httpx SDK's `CONNECT` requests were rejected with `407 Proxy Authentication Required` and every proxied LLM call failed. The proxy URL in step 5 is now `http://${VAULT_TOKEN}@agent-vault:14322`; httpx parses the embedded credentials and sends the required `Proxy-Authorization` header automatically.
- **`provision-tenant-vault` step 5 did not set `SSL_CERT_FILE`, causing SSL verification failures.** The Dockerfile installs the Agent Vault self-signed MITM CA into the system CA bundle via `update-ca-certificates`, but Python's `ssl` module (used by httpx/openai SDK) defaults to the `certifi` bundle, which does not include it. Without `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, TLS verification of the intercepted connection failed even when the CA was correctly installed in the image. Step 5 now appends `SSL_CERT_FILE` to the injected proxy config block.
- **`platform/templates/_base/env.template` proxy stub did not reflect the token-in-URL format or `SSL_CERT_FILE`.** Updated to match the corrected SOP output.

### Changed
- README Credential Security Model step 3 updated to document that the proxy token is embedded in the `HTTP_PROXY`/`HTTPS_PROXY` URL and that `SSL_CERT_FILE` is required for Python SSL trust.

### Follow-up (operator action required)
- Tenants provisioned before this release (`u-moon-cafe`, `vrewards`, and any others) have the old proxy URLs and are missing `SSL_CERT_FILE`. Update each affected tenant's `.env` by embedding the existing `AGENT_VAULT_TOKEN` value into the proxy URL and appending `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, then force-recreate the container.

### Added
- **Per-tenant knowledge vault: an Obsidian-compatible second brain for each tenant business.** New per-tenant directory `/opt/aaas/tenants/{tenant-id}/vault/` (mounted into the container at `/home/hermes/vault`) holds curated, structured Markdown notes (`Customers/`, `Suppliers/`, `Recurring/`, `Reference/`) maintained by the tenant agent itself at runtime — not the admin agent. This is a third tenant-side knowledge system alongside Mnemosyne (in-conversation recall) and `business-data.md` (today's prices/menu/hours); none of the three overlap by design.
  - New tenant-side script `platform/scripts/tenant/vault-init-tenant.sh`, copied into the tenant volume and run inside the container (same pattern as `skill-verify.sh`). Idempotent — safe to re-run, never overwrites existing tenant notes. Also closes a pre-existing gap where `scripts/tenant/skill-verify.sh` itself was missing from the installer's repository-asset and validate-only checks.
  - `templates/_base/SOUL.md.template` now teaches the tenant agent the three-way split between Mnemosyne, `business-data.md`, and the knowledge vault, plus the exact decision rule for classifying a new fact into the right one. This is the most important change in this release — the prompt the tenant agent actually reads at runtime, not just platform documentation.
  - `sop/onboard-tenant.md` step 4.2 scaffolds the vault before the ownership pass, and step 8's compose service now mounts `vault -> /home/hermes/vault` alongside the existing `files` mount.
  - `sop/update-tenant.md` and `sop/upgrade-tenants.md` back-fill the vault (and its compose mount) for tenants onboarded before this feature existed.
  - `sop/troubleshoot-tenant.md` adds a "Knowledge Vault Missing, Not Mounted, Or Not Owned" recovery path, distinct from the existing Mnemosyne recovery path.
  - `harness/check-tenant.sh` and `scripts/validate-tenant-config.sh` verify the vault directory, its `README.md`, UID 10000 ownership, the compose mount, and that `SOUL.md` documents both the vault and `business-data.md`.
  - `harness/tenant-harness.yaml.template` and `harness/ACCEPTANCE.md.template` add the knowledge vault as a required check and an owner-benefit/platform-check item respectively.
  - `AGENTS.md` and `README.md` spell out all four similarly-named systems (Agent Vault, Mnemosyne, business-data.md, and now two knowledge vaults — platform-level and per-tenant) so the distinction is never ambiguous to whoever reads them next.
  - **Correction:** the tenant agent has no `platform/skills/`-style skill loader the way the admin agent does, so it cannot use `query-knowledge-vault.md` or `sync-knowledge-vault.md` (which are admin-agent-only, and only ever touch `/opt/aaas/platform/vault` on the host — unreachable from inside a tenant container). The tenant agent's own "search before writing a new note" habit is instead written directly into `SOUL.md.template`, backed by a "For the assistant" reference section at the bottom of the tenant's generated `vault/README.md`. `AGENTS.md`, `README.md`, and both vault-related skill/SOP files now state this admin/tenant boundary explicitly rather than leaving it implied by file path alone.

## 0.8.0 - 2026-06-28

### Added
- **Knowledge vault: an Obsidian-compatible second brain for the platform.** New managed directory `platform/vault/` holds curated, cross-linked Markdown notes (`Tenants/`, `Incidents/`, `SOPs/`, `Platform/`, `Daily/`) separate from the raw `reports/` audit trail and `INDEX.jsonl` machine index. Scaffolded automatically on install/upgrade via the new `platform/scripts/vault-init.sh` (idempotent; never overwrites existing notes), with a minimal `.obsidian/app.json` so the folder opens cleanly in the Obsidian app with no community plugins required.
  - New SOP `platform/sop/sync-knowledge-vault.md`: when and how to turn a task report into a durable vault note. Non-blocking — a missing or failed vault sync never fails the originating SOP or report.
  - New skill `platform/skills/query-knowledge-vault.md`: search the vault for prior tenant/incident/SOP history before troubleshooting or proposing changes.
  - `platform/sop/write-report.md`, `platform/sop/improve-sop.md`, and `platform/sop/troubleshoot-tenant.md` now reference the vault sync/query steps at the appropriate points in their flow.
  - `AGENTS.md` documents the vault path and rules, and is explicit that it is unrelated to Agent Vault (credential storage) and Mnemosyne (per-tenant runtime memory) despite the similar name.
  - README adds a "Knowledge Vault" section describing the layout and usage.

## 0.7.3 - 2026-06-28

### Fixed
- Move scripts/agent-vault-health.sh → platform/scripts/agent-vault-health.sh.
- Some fixes based on runtime upgrade reports.

## 0.7.2 - 2026-06-28

### Fixed
- **Dockerfile missing Agent Vault MITM CA trust block:** the repo Dockerfile did not include the `COPY agent-vault-ca.pem` and `update-ca-certificates` steps that are required for TLS interception to work. Tenant image builds would succeed but every proxied LLM call would fail with a TLS certificate error. The Dockerfile now ships with the CA installation block in place. The CA itself is self-generated by Agent Vault on first boot (no third-party certificate authority involved); `setup-agent-vault.md` step 3 fetches it from the running container and places it in the Docker build context.
- **`setup-agent-vault.md` step 4 incorrectly told operators to manually patch the Dockerfile:** now that the Dockerfile ships with the CA block, step 4 is a verification step (confirm the block is present) rather than an edit step.
- **`validate_install` did not check for the CA trust block or the CA certificate file:** added checks that the Dockerfile contains the `agent-vault-ca.crt` line and that `agent-vault-ca.pem` is present in the Docker build context directory. Without these checks, a platform install could pass validation while being unable to build a working tenant image.
- **`agent-vault-failure.md` Recovery A and C used bare `docker compose` without `-f`:** the Agent Vault compose file lives at `/opt/aaas/agent-vault/docker-compose.yaml`, not in `/opt/aaas/platform/docker/`. Running `docker compose up -d agent-vault` from the platform directory would fail with "no such service". All three recovery commands now use `docker compose -f /opt/aaas/agent-vault/docker-compose.yaml`.
- **`update-tenant.md` step 2 listed "LLM API key" as an updatable item and step 3 pointed to `.env` for secrets without excluding the LLM key:** following this SOP for a key-change request would have written a live key back to `.env`, bypassing Agent Vault entirely. LLM API keys are now explicitly out of scope for this SOP; the step 2 list no longer includes them and step 3 notes that the LLM key placeholder must not be changed.
- **`onboard-tenant.required.json` had no gate for vault provisioning:** the checklist could pass even if `provision-tenant-vault` was skipped, leaving a tenant with a real API key in `.env`. Added `tenant_vault_provisioned_and_key_scrubbed` as a required completion gate.
- **`monitor-health.required.json` had no gate for Agent Vault health:** the monitor-health SOP step 0.1 requires running `agent-vault-health.sh` first, but the binding checklist had no corresponding item. Added `agent_vault_health_checked` as the first required gate.
- **`admin-hermes/env.template` was missing `OPENCODE_API_KEY`:** the 0.7.1 release added OpenCode Zen support to the tenant env template and setup-admin-hermes skill but missed the admin-hermes template. Added as a commented entry alongside the other provider placeholders.

### Removed
- **LLM API key rotation via `agent-vault vault credential update` is no longer documented as a supported self-service operation.** The command itself still works but the operational complexity (re-fetching a new token, recreating containers when tokens change, keeping `.env` in sync) made it error-prone as a routine SOP step. To change a tenant's LLM API key, contact the platform operator to update it directly in Agent Vault, or offboard and re-onboard the tenant. Removed the rotation section from `provision-tenant-vault.md`, the rotation rule from `AGENTS.md`, the rotation bullet from the README Use OpenCode list, and the rotation code block from the README Credential Security Model section.

## 0.7.1 - 2026-06-28

### Added
- OpenCode Zen as a supported LLM provider across the platform. Tenant agents can now use the OpenCode Zen gateway (`opencode.ai/zen/v1`) with `OPENCODE_API_KEY` as the credential env var.
  - `platform/sop/provision-tenant-vault.md`: added OpenCode Zen row to the provider hostname table (`opencode.ai`). The MITM proxy intercepts outbound calls to `opencode.ai` and injects the real key from Agent Vault.
  - `platform/templates/_base/env.template`: added `# OPENCODE_API_KEY=routed-via-agent-vault` as a commented example alongside the existing provider placeholders.
  - `platform/skills/setup-admin-hermes.md`: added OpenCode Zen (`OPENCODE_API_KEY`) to the provider key examples for the optional Hermes admin agent.

### Fixed
- `platform/sop/provision-tenant-vault.md`: corrected Agent Vault hostname for OpenCode Zen to `opencode.ai` (not `api.opencode-zen.com`, which does not resolve).
- **Tenant containers failing to start (network not found):** `setup-platform.sh`'s `setup_agent_vault()` created the `agent-vault-net` network without pinning a literal `name:`, so Compose project-prefixed it to `agent-vault_agent-vault-net`. The tenant Compose file's `agent-vault-net: external: true` block looked for the unprefixed name and never found it, so `docker compose up -d hermes_{tenant-id}` failed for every tenant onboarded after 0.7.0. Both the vault's own `docker-compose.yaml` and the tenant Compose network block now pin `name: agent-vault-net` explicitly. Added a `validate_install` check to catch a regression of this.
- **Real LLM API key left in `.env` for non-OpenAI tenants:** `provision-tenant-vault.md` step 5 hardcoded `OPENAI_API_KEY` in its placeholder-substitution command, so the real key was never scrubbed for Anthropic, OpenRouter, or Nous tenants — the three of four supported providers most likely to be in use. The SOP now uses the exact provider env var name collected during onboarding (step 1) instead of a hardcoded default.
- **Key-scrub verification could never actually fail (or pass) correctly:** the same SOP's "verify the key is gone" check grepped for `key=` case-insensitively, which always matches the env var's own name (e.g. `ANTHROPIC_API_KEY=`) regardless of its value, so "Expected: no output" was unreachable even when scrubbing worked correctly. Replaced with two checks: one confirming the provider var holds the literal placeholder, and one scanning for live-looking key prefixes. Also reordered the SOP so the key is scrubbed *before* this verification runs, rather than after (previously the check ran a full step before the substitution that was supposed to make it pass).
- **README listed the wrong file as holding the Agent Vault master password:** the preserved-paths list named `/opt/aaas/platform/docker/.env`, a file no installer script creates. The actual master password lives in `/opt/aaas/agent-vault/.env` (a separate directory tree, peer to `platform/`), which was previously absent from any backup/preserved-path guidance entirely. Corrected the path and added a pointer to the master-password-loss recovery procedure.

### Changed
- `provision-tenant-vault.md`: tenant `.env` now also receives a `NO_PROXY` entry (Telegram, localhost) so only the registered LLM provider host is routed through Agent Vault's MITM proxy — previously `HTTP_PROXY`/`HTTPS_PROXY` were set with no scoping, routing all outbound tenant traffic (including Telegram bot traffic) through the proxy by default.
- `provision-tenant-vault.md`: added a step to set each tenant vault's unmatched-host policy to deny. Agent Vault's documented default is to forward requests to unregistered hosts as plain passthrough rather than blocking them; left at the default, a compromised or misbehaving tenant container retained effectively unrestricted internet egress through the proxy, undermining the credential-isolation goal of adopting Agent Vault in the first place.
- `platform/templates/_base/env.template`: added a `NO_PROXY` stub alongside the other Agent Vault proxy vars.
- `platform/AGENTS.md`: strengthened the "never store real keys" and key-rotation rules to call out the provider-var requirement and the new egress-scoping behaviour.
- `README.md`: Credential Security Model section now documents the egress-scoping step (`NO_PROXY` + deny policy) as part of the credential flow.

## 0.7.0 - 2026-06-26

### Added
- Integrated [Agent Vault](https://github.com/Infisical/agent-vault) as the platform credential broker. Real LLM API keys are now stored exclusively in Agent Vault and injected at the network layer via MITM proxy. Tenant containers never hold live credentials.
- `platform/sop/setup-agent-vault.md`: post-install SOP covering the operator steps that require a running container — account registration, MITM CA fetch, Dockerfile patch, and tenant image rebuild. Heavy lifting (directory creation, Compose file, image pull, container start) is handled automatically by `setup-platform.sh`.
- `platform/sop/provision-tenant-vault.md`: sub-SOP called from `onboard-tenant` (step 6.3) to create a scoped vault per tenant, store the real LLM key, mint a proxy agent token, and write proxy vars into the tenant `.env`.
- `platform/sop/deprovision-tenant-vault.md`: sub-SOP called from `offboard-tenant` (step 6.1) to cascade-delete the tenant vault, credentials, and agent tokens from Agent Vault.
- `platform/scripts/agent-vault-health.sh`: checks Agent Vault container state, Docker health status, management API reachability, MITM proxy port reachability, and CLI authentication. Returns PASS/WARN/FAIL per check.
- `platform/incidents/agent-vault-failure.md`: incident runbook with three recovery paths — container crashed, database lost, and master password lost.

### Changed
- `scripts/setup-prerequisites.sh`: updated "next steps" message to explain the full Agent Vault setup flow across both scripts. Agent Vault CLI install (Step 7) and `/opt/aaas/agent-vault/data` directory creation (Step 8) were already present from the previous session.
- `scripts/setup-platform.sh`: added `setup_agent_vault()` call to the main install flow (after `install_assets`). The function creates `/opt/aaas/agent-vault/` as a peer to `platform/` (not inside it), writes a standalone `docker-compose.yaml` and `.env` stub, pulls the image, and starts the container if the master password is already set. Added Agent Vault infrastructure existence checks to `validate_install`. Updated "next steps" message to branch on whether the master password is set. Added `agent-vault` CLI check to `ensure_plan0_ready`.
- `platform/sop/onboard-tenant.md`: added step 6.3 (call `provision-tenant-vault` after `.env` is created, before container start) and updated step 8 to attach tenant service to `agent-vault-net`.
- `platform/sop/offboard-tenant.md`: added step 6.1 to call `deprovision-tenant-vault` before tenant data deletion.
- `platform/sop/monitor-health.md`: added step 0.1 to run `agent-vault-health.sh` before checking tenants — vault down means all LLM calls fail.
- `platform/scripts/preflight-check.sh`: added Agent Vault container check (WARN-level so platforms not yet migrated are not blocked).
- `platform/templates/_base/env.template`: LLM provider key vars now use the `routed-via-agent-vault` placeholder; added `HTTP_PROXY`, `HTTPS_PROXY`, `AGENT_VAULT_ADDR`, `AGENT_VAULT_TOKEN`, and `AGENT_VAULT_VAULT` stubs with a note that `provision-tenant-vault` fills them in.
- `platform/AGENTS.md`: registered new SOPs and health script; added rules — Agent Vault must be set up before first tenant, never store real keys in `.env`, always call provision/deprovision SOPs, rotate keys via vault (no container restart needed).
- `README.md`: added credential security model section, Agent Vault first-time setup instructions, key rotation example, updated preserved-paths list and monitoring section.

## 0.6.1 - 2026-06-24

### Fixed
- Removed dead host-path variables (`PLATFORM_ROOT`, `EVAL_JUDGE`, `ADMIN_ENV`, `ADMIN_HERMES`)
  from `skill-verify.sh`. These referenced `/opt/aaas/platform` paths that do not exist inside
  the tenant container.
- Rewrote `run_judge_fallback()` to unconditionally record `WARN` + `provisional` with a clear
  reason, instead of conditionally attempting host calls. Judge verification has always been
  provisional-forever by design; the implementation now matches that intent.
- Updated `_skill-verification-primitives-v1.yaml` judge fallback description to state explicitly
  that it cannot be auto-verified inside the tenant container and requires operator review.

### Changed
- Moved `skill-verify.sh` from `platform/scripts/` to `platform/scripts/tenant/` to make the
  host/tenant script boundary structurally obvious. All other scripts in `platform/scripts/`
  remain host-only and keep their existing paths.
- Added step 6.2 to `onboard-tenant.md` SOP: copy `skill-verify.sh` into the tenant volume at
  `tenants/{tenant-id}/scripts/skill-verify.sh` during onboarding so the container can call it
  at `/opt/data/scripts/skill-verify.sh` at runtime. This closes the delivery gap - the script
  previously existed on the host but had no mechanism to reach the container.

## 0.6.0 - 2026-06-24

### Added
- Added a vertical-agnostic professional-conduct block to `SOUL.md.template`:
  ask before assuming, attempt before declining, disclose when blocked, report
  progress on long tasks, and codify solved tasks as skills.
- Added `platform/evals/tenant-agent/_skill-verification-primitives-v1.yaml`,
  a fixed library of verification primitive types for self-written tenant skills.
- Added `platform/scripts/skill-verify.sh`: automated, human-independent
  verification of self-written tenant skills (deterministic checks plus an
  optional isolated judge fallback), and a per-tenant skill provenance ledger
  at `skills/PROVENANCE.jsonl`.
- Extended `_fixed-safety-v1.yaml` with `attempts_before_declining`,
  `discloses_when_blocked`, and `reports_progress_on_multistep_task` checks.
- Extended `check-tenant.sh` with conduct-block and provenance-file checks.

### Changed
- `_fixed-safety-v1.yaml` bumped to version 2.

## 0.5.3 - 2026-06-24

- Enabled Docker to start automatically on system boot during prerequisites setup when `systemd` is available.
- Added preflight validation for `docker.service` boot enablement on systemd hosts.
- Replaced tenant-facing `~/files/...` paths with absolute `/home/hermes/files/...` paths in base SOUL/MEMORY templates, onboarding docs, acceptance checks, and fixed safety evals so agents use the mounted tenant files directory consistently.
- Updated the tenant harness SOUL path checks to require `/home/hermes/files/generated` and `/home/hermes/files/uploads`.

## 0.5.2 - 2026-06-23

### Changed
- Updated the tenant update SOP to recreate only the affected tenant container with `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}` after config, secret, or model provider changes.
- Added admin-agent rules forbidding single-tenant recovery via broad `docker compose down` and forbidding `docker compose restart` for changes that need a clean reload.
- Documented the single-tenant clean reload rule in the README.
- Added `CHANGELOG.md` to managed install and upgrade assets so release notes are available under `/opt/aaas/platform/CHANGELOG.md`.
- Clarified that task reports must be written as flat report files directly under `/opt/aaas/platform/reports/`, not SOP/category subfolders.
- Added `restart: unless-stopped` as a required tenant compose policy and harness check so tenants recover after host or Docker daemon restarts.
- Added harness validation for tenant compose `mem_limit` and `cpus` resource limits, matching the Compose v2 service reference.

## 0.5.1 - 2026-06-22

### Fixed
- Corrected the fixed safety eval `respects_upload_folder` file existence check to verify generated output under `/home/hermes/files/generated/`.
- Aligned `eval-runner.sh` with the documented interface: `eval-runner.sh {tenant-id} {path-to-eval-file}`.
- Updated onboarding, update, troubleshooting, AGENTS, tenant setup docs, and README references to the tenant-id-first eval runner usage.
- Replaced the admin generation meta-eval with the planned `profile_id`, `business_name`, `location`, and `given_facts` schema.
- Added explicit onboarding guidance for semantic eval `SKIP` output and exit-code-2 manual-review fallback.

### Changed
- README now documents the two-layer tenant eval flow and the eval runner behavior.

## 0.5.0 - 2026-06-22

### Added
- Added generated vertical behavior support for onboarding through `VERTICAL_CAPABILITIES_BLOCK` and `VERTICAL_BRAND_FACTS_BLOCK` template placeholders.
- Added base tenant memory template at `platform/templates/_base/MEMORY.md.template`.
- Added fixed safety eval profile at `platform/evals/tenant-agent/_fixed-safety-v1.yaml`.
- Added generated per-tenant eval directory at `platform/evals/tenant-agent/generated/`.
- Added tenant eval runner scripts: `eval-runner.sh`, `_eval-check-single.sh`, and `eval-judge.sh`.
- Added admin-agent meta-eval profile for vertical generation quality checks.

### Changed
- Updated onboarding, update, troubleshooting, AGENTS, tenant setup docs, harness templates, and setup validation for fixed-plus-generated eval profiles.
- Updated tenant harness checks for fixed safety profile presence, generated tenant eval presence, and stronger fixed safety wording.
- Updated setup installation validation and install-time chmod handling for the new eval assets and scripts.

### Removed
- Removed predefined vertical template folders under `platform/templates/verticals/`.
- Removed the old fixed F&B tenant eval profile `fnb-marketing-v1.yaml`.