# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

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