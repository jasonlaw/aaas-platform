# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

## 0.15.3 - 2026-07-03

### Added
- **`platform/scripts/add-tenant-compose-service.sh`** (new) — deterministic replacement for the prose-described YAML block that `onboard-tenant.md` step 8 previously asked the agent to write by hand into `docker-compose.yaml`. The script appends the complete, correctly indented service block (image, command, restart policy, mounts, env_file, resource limits, network, healthcheck, watchdog labels) and the required `external: true` + `name:` network declaration at the bottom of the file. A duplicate-guard prints `SKIP` if the service is already present rather than appending a second block. `onboard-tenant.md` step 8 now calls this script; the prose bullet list describing each YAML field is removed.
- **`platform/scripts/diagnose-tenant-logs.sh`** (new) — pattern-matches the last N tenant container log lines against the platform's known error vocabulary (permission denied → `chown`/`chmod` repair; Agent Vault proxy auth/SSL/connection failures; Mnemosyne data-dir mismatch or seed failure; iptables/network unreachable; config parse errors; plugin reconcile failures; container stopped/entrypoint error) and prints each finding with its named category and the exact recovery command from `troubleshoot-tenant.md`. Falls back to a `none / no_known_patterns_matched` result for unrecognised output rather than silently passing. `troubleshoot-tenant.md` step 8 now calls this script first; raw `docker logs` is the fallback for unmatched output.

### Fixed
- **`platform/harness/check-tenant.sh` did not verify three compose properties that `add-tenant-compose-service.sh` now guarantees.** The watchdog labels (`aaas.watchdog`, `aaas.watchdog.priority`, `aaas.watchdog.playbook`), the process-based `healthcheck`, and the `external: true` + `name:` network block at the bottom of `docker-compose.yaml` were all required by prose in `onboard-tenant.md` step 8 but never asserted by the harness — meaning a hand-written or partially generated block could silently omit them and still pass all harness checks. Added six new `service_contains`/`contains` checks covering all three properties; they pass against output from `add-tenant-compose-service.sh` by construction.
