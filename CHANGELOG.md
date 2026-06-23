# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## 0.5.2 - 2026-06-23

### Changed
- Updated the tenant update SOP to recreate only the affected tenant container with `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}` after config, secret, or model provider changes.
- Added admin-agent rules forbidding single-tenant recovery via broad `docker compose down` and forbidding `docker compose restart` for changes that need a clean reload.
- Documented the single-tenant clean reload rule in the README.

## 0.5.1 - 2026-06-22

### Fixed
- Corrected the fixed safety eval `respects_upload_folder` file existence check to verify generated output under `~/files/generated/`.
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