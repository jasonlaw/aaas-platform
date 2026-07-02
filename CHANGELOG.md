# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

## 0.15.5 - 2026-07-03

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

## 0.15.4 - 2026-07-03

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
