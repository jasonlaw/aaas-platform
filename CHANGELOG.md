# Changelog

All notable changes to this platform setup are tracked here. The platform setup version is stored in `platform/VERSION`.

## Unreleased

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
