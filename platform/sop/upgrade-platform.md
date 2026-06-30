# SOP: Upgrade Platform Setup

## Purpose
Upgrade the installed platform assets to the latest repository version while preserving tenant data, tenant registry, Docker Compose services, and historical reports.

## What This Upgrades
- `/opt/aaas/platform/AGENTS.md`
- `/opt/aaas/platform/VERSION`
- `/opt/aaas/platform/sop/`
- `/opt/aaas/platform/skills/`
- `/opt/aaas/platform/tenant-hermes/`
- `/opt/aaas/platform/harness/`
- `/opt/aaas/platform/checklists/`
- `/opt/aaas/platform/policy/`
- `/opt/aaas/platform/evals/` (admin meta-eval profile; tenant eval profiles are covered by `tenant-hermes/` above)
- `/opt/aaas/platform/scripts/`
- `/opt/aaas/platform/incidents/`
- `/opt/aaas/platform/docker/Dockerfile`
- Setup validation behavior from the latest script
- `/opt/aaas/platform/admin/SOUL.md` and `/opt/aaas/platform/admin/config.yaml` — checked for drift against their current templates and refreshed only with operator confirmation (step 9.3); not overwritten automatically like the other items above
- `/opt/aaas/platform/admin/.env` — checked only for missing required key *names* added since last setup (step 9.4); secret values are never touched or compared

## What This Must Preserve
- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
- `/opt/aaas/platform/reports/`
- Existing tenant containers unless a separate tenant/image upgrade is requested

## Steps
0. **Precondition: this SOP is OpenCode-only.** If you are the Hermes admin agent (not an interactive OpenCode session), stop here — do not proceed to step 1. Notify the operator that a platform upgrade is available/requested and that it must be run from an interactive OpenCode session at the host (`cd /opt/aaas/platform && opencode`).
1. Read current installed version:
   `cat /opt/aaas/platform/VERSION 2>/dev/null || echo "unknown"`
2. Read recent platform upgrade reports before proceeding:
   `grep '"sop":"upgrade-platform"' /opt/aaas/platform/reports/INDEX.jsonl | tail -n 10`
3. **Verify iptables state before proceeding:**
   - `iptables --version` must show `legacy`. If it shows `nf_tables`, switch with:
     `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - Alert operator that Docker daemon was restarted; all tenant containers must be restarted after the platform upgrade completes
4. Explain to the operator that this upgrades platform assets only. It does not migrate tenant data, rebuild the tenant Docker image, or restart tenant containers unless explicitly requested.
5. Ask for confirmation: "Proceed with platform upgrade? (y/n)"
6. Run the latest setup installer. On an existing platform it auto-detects upgrade mode and skips image rebuild by default. If the installed `VERSION` already matches the repository `VERSION`, choose whether to continue with a backup, continue without a backup, or cancel:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash`
7. Validate the installed platform:
   `curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --validate-only`
8. Read the new installed version:
   `cat /opt/aaas/platform/VERSION`
9. Check that preserved files still exist:
   `test -f /opt/aaas/platform/tenants.yaml`
   `test -f /opt/aaas/platform/docker/docker-compose.yaml`
   `test -f /opt/aaas/platform/reports/INDEX.jsonl`
9.1. **Regenerate the fixed safety eval profile** in case `platform-policy.yaml` changed in this version:
   `/opt/aaas/platform/scripts/generate-platform-eval.sh`
   `/opt/aaas/platform/scripts/validate-platform-rules.sh`
   If validation fails, do not proceed to tenant backfill — report the failure and stop; a platform-policy.yaml rule shipped without matching eval coverage.
9.2. Run the upgrade-tenants SOP to backfill all active tenants onto this version, including re-rendering each tenant's `SOUL.md` policy blocks and isolated network if missing — see `upgrade-tenants.md` step 3.
9.3. **Check the admin agent's own `SOUL.md` and `config.yaml` for drift against their current templates.** Unlike tenant `SOUL.md`/`config.yaml` (re-rendered every upgrade via step 9.2) or `AGENTS.md` (overwritten wholesale every upgrade via step 6), `setup-admin-hermes.md` Step 2 copies these into `/opt/aaas/platform/admin/` exactly once and nothing else in this repo ever touches them again — so they can silently fall behind the shipped templates. This already happened for real with `config.yaml`: it gained a Telegram `gateway` block in 0.13.1 and had a wrong comment fixed in 0.13.2, and any admin instance set up before either release kept the stale file with nothing flagging it. Skip this step entirely if `/opt/aaas/platform/admin/SOUL.md` does not exist (admin Hermes not yet set up on this host).
    ```bash
    diff -u /opt/aaas/platform/admin/SOUL.md /opt/aaas/platform/admin-hermes/SOUL.md.template
    diff -u /opt/aaas/platform/admin/config.yaml /opt/aaas/platform/admin-hermes/config.yaml.template
    ```
    - If a file shows no diff, nothing to do for it.
    - If a file shows a diff, show it to the operator separately. Some of it may be the operator's own intentional customization (tone or extra rules in `SOUL.md`; provider, model, dashboard host/port, or Telegram settings in `config.yaml`) — never overwrite blindly. Ask per file: "{file} differs from the current template. Apply the new template, keeping a backup of the current file? (y/n)"
    - If yes for a file: back it up (`cp /opt/aaas/platform/admin/{file} /opt/aaas/platform/admin/{file}.bak-{timestamp}`), then either replace it with the template or merge in just the new/changed lines, whichever the operator prefers. For `config.yaml`, preserve the operator's existing `provider`, `default` model, `dashboard.host`/`dashboard.port`, and any `gateway.platforms.telegram` block when merging — only the surrounding structure and invariant lines (`memory_enabled: false`, `user_profile_enabled: false`, `provider: mnemosyne`) should come from the template. Re-run the content checks in `setup-admin-hermes.md` Step 6 against the result.
    - If no for a file: record in the task report that it was left as-is and may be missing changes from the current template, so this is visible on review rather than silently skipped.
    - Restart Hermes admin after any change so the running agent picks up the new file(s): `/opt/aaas/platform/scripts/hermes-admin-watchdog.sh` will not do this on its own since it only acts when the process is unresponsive, not when its config changed — restart it directly per `setup-admin-hermes.md` Step 7.
9.4. **Check the admin agent's `.env` for required keys added since it was last set up.** `.env` holds real operator secrets and must never be diffed wholesale or auto-overwritten the way 9.3 handles `SOUL.md`/`config.yaml` — every real value legitimately differs from the placeholder template by design. Instead, only check that every key *name* the current `env.template` expects (commented or not) is present in the live file; this catches additions like `TELEGRAM_HOME_CHANNEL` in 0.13.1 without ever touching a secret value. Skip if `/opt/aaas/platform/admin/.env` does not exist.
    ```bash
    for key in $(grep -oE '^#?\s*[A-Za-z_]+=' /opt/aaas/platform/admin-hermes/env.template | sed -E 's/^#\s*//; s/=$//' | sort -u); do
      grep -q "^${key}=\|^# ${key}=" /opt/aaas/platform/admin/.env \
        || echo "MISSING: ${key}"
    done
    ```
    - If any keys are reported missing, tell the operator which ones and add each as a commented-out line (matching the template's default state) unless the operator wants to enable that feature now, in which case follow the relevant section of `setup-admin-hermes.md` (e.g. Step 3.1 for Telegram keys) to set it properly instead of just stubbing it in.
    - Never write a real secret value into `.env` as part of this check — only add the key name, commented out, if its purpose isn't being enabled right now.
10. **Post-upgrade iptables verification:**
    - `iptables --version` must still show `legacy`. If it reverted to `nf_tables`, switch again and restart Docker
    - `sudo iptables -L DOCKER-FORWARD -n | head -5` should show bridge forwarding rules
    - If rules are missing, run the health monitor SOP to detect and repair
11. If the new platform version changes the Dockerfile or template behavior and tenant image rebuild is needed, ask the operator before running the build image SOP. Do not rebuild automatically.
12. **If Docker daemon was restarted during this upgrade:** Restart all active tenants to ensure they re-establish outbound connectivity:
    `for tenant in $(grep 'status: active' /opt/aaas/platform/tenants.yaml | awk '{print $2}'); do docker compose up --force-recreate --no-deps -d hermes_$tenant; done`
    Then run the health monitor SOP to verify outbound connectivity for all tenants.
13. Write a task report using `/opt/aaas/platform/sop/write-report.md` with `sop` set to `upgrade-platform`.

## Recovery
- The installer backs up managed platform assets under `/opt/aaas/platform/backups/` before versioned upgrades and when the operator chooses the backup option on a same-version rerun.
- If validation fails, inspect the newest backup folder and restore only the affected managed asset. Do not restore `tenants.yaml`, `docker-compose.yaml`, reports, or tenant directories from platform asset backups.

## Rules
- Never delete tenant data during platform upgrade.
- Never overwrite `tenants.yaml` or `docker-compose.yaml` if they already exist.
- Never truncate or rewrite `reports/INDEX.jsonl`.
- Treat tenant Docker image upgrades as separate work through `build-image.md` and `upgrade-tenants.md`.
