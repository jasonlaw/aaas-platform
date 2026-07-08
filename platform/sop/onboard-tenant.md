# SOP: Onboard New Tenant

## Purpose
Provision a new Hermes tenant agent as a Docker container.

## Pre-requisites
- Telegram bot token ready
- Tenant LLM API key ready
- Host system has iptables in legacy mode (verify with `iptables --version` - must not show `nf_tables`)
- Docker daemon is running and responsive

## Steps
0. **Pre-flight check:** Verify the host has iptables in legacy mode and Docker is responsive:
   - `iptables --version` must show `legacy` (not `nf_tables`). If not, switch with: `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && sudo systemctl restart docker`
   - `docker ps` must succeed without errors
   If checks fail, abort and report the issue before proceeding.
0.1. Read `/opt/aaas/platform/checklists/onboard-tenant.required.json`. Treat every item as a completion gate; unresolved items must appear in the final task report.
0.2. Run `/opt/aaas/platform/scripts/preflight-check.sh`. Inspect the output:
   - If it fails on `hermes_tenant_image_missing`: the tenant image has not been built yet. Build it now before doing anything else:
     ```
     /opt/aaas/platform/scripts/setup-platform.sh --build-image
     ```
     Re-run `preflight-check.sh` after the build completes and confirm `hermes_tenant_image_exists` passes before continuing.
   - If it fails on any other check: fix the reported host/platform issue before creating any tenant files.
   - If it only has warnings (no failures): continue — warnings are informational.
0.3. Confirm `/opt/aaas/platform/tenant-hermes/evals/_skill-verification-primitives-v1.yaml`
exists (platform-level asset, not generated per tenant). If missing, the platform
setup is out of date - do not attempt to author it inline; report this and stop.
0.4. Confirm `/opt/aaas/platform/policy/platform-policy.yaml` exists (platform-level
asset, not generated per tenant). If missing, the platform setup is out of date -
do not attempt to author it inline; report this and stop.
1. **Collect tenant information using a two-phase interview: essentials first, then optional refinements.**

   **Design principle:** Most fields have sensible defaults. Present each default inline so the operator can accept it with a single word or skip past it — they only need to type when the default is wrong. The agent's personality and capabilities can always be tuned later; getting the bot running fast is the priority. Every item in both phases below is answered directly in the reply to one grouped message — never split any of them into a separate button-based question per item, and never add a button whose only purpose is "I'll provide it" in front of a field that's already asking the operator to provide a value.

   **Phase 1 — Essentials (always ask, no defaults possible):**
   Ask these as a single grouped message so the operator can reply to all at once:

   > **Quick setup — 5 things needed to get started:**
   > 1. **Business name** — what should the agent call itself?
   > 2. **Business type & what you do** — e.g. "pet grooming salon, dogs and cats, appointment-only"
   > 3. **Location** — city/region, e.g. "Kuala Lumpur, Malaysia"
   > 4. **Telegram bot token** — from @BotFather
   > 5. **Your Telegram user ID(s)** — numeric IDs allowed to use this bot (comma-separated if multiple)
   >
   > *(That's all that's required to go live. Everything else has a sensible default you can change later.)*

   **Home channel:** `TELEGRAM_HOME_CHANNEL` is the single primary contact
   for Hermes-initiated messages (alerts, restart notifications) — same
   convention as admin Hermes (see `skills/setup-admin-hermes.md` Step
   3.1). If item 5 above has exactly one ID, use it automatically — no
   extra question needed. If it has more than one, ask the owner to pick
   one as a single-select choice; this field accepts exactly one ID,
   never a list.

   **Phase 2 — Optional refinements (show defaults, let operator accept or override):**
   After Phase 1 answers are received, present the following as a single confirmation block with pre-filled defaults. The operator can reply "all good" or list only the items they want to change:

   > **Here are the defaults for everything else — reply "ok" to accept, or tell me which ones to change:**
   >
   > - **Language:** English *(change if the agent should reply in another language)*
   > - **Brand tone:** Professional and a little playful *(e.g. "formal", "warm and casual", "fun and emoji-friendly")*
   > - **Primary colour:** #2563EB (blue) *(hex code for brand assets)*
   > - **Secondary colour:** #FFFFFF (white)
   > - **Owner/contact name:** *(skipped — agent will refer to owner by business name unless you tell me a name)*
   > - **LLM provider/model:** openrouter/google/gemini-2.0-flash-001 *(change if you have a preferred provider and API key)*
   > - **LLM API key:** *(required only if you changed the provider above — otherwise paste your OpenRouter key)*
   > - **Fallback provider:** None *(optional — Hermes auto-switches mid-turn if the primary provider fails)*
   > - **Access restrictions:** None *(optional — e.g. "only allow posting to Instagram, not Facebook")*
   > - **Website / social links:** None *(optional — homepage, Facebook, Instagram; the agent will look these up itself when it's natural to, and check what it finds with you)*

   **Defaults used when the operator accepts without changes:**
   | Field | Default |
   |---|---|
   | language | English |
   | brand_tone | "professional and a little playful" |
   | communication_style | "friendly, concise" |
   | primary_color | #2563EB |
   | secondary_color | #FFFFFF |
   | owner_name | *(omitted — use business name)* |
   | llm_provider | openrouter |
   | llm_model | google/gemini-2.0-flash-001 |
   | fallback_providers | *(none)* |
   | tenant_access_restrictions | *(none)* |
   | timezone | inferred from location (if ambiguous, ask) |
   | industry_details | business type + description as given in step 1 |
   | business_links | *(none)* |

   **Never ask the operator for the provider-specific API key env var name — that is always derived, not collected.** Accept the LLM provider/model in whatever form the operator gives it (`provider/model`, e.g. `openrouter/google/gemini-2.0-flash-001`; or separate `provider =` / `model =` answers), split out the Provider ID, and look it up in `/opt/aaas/platform/reference/llm-provider-catalog.md` to get both the hostname (needed later in `provision-tenant-vault.md` step 2) and the env var name (via the catalog's deterministic derivation rule). Only fall back to asking the operator a follow-up question if the named provider isn't in the catalog (ask for its API hostname only, never the env var name — see the catalog's "Provider not in this table" section) or if it falls under the catalog's Exceptions section (OAuth-only or multi-credential providers), in which case follow that section's escalation guidance instead of proceeding. Same rule applies to the optional fallback provider if one is collected.
1.1. **Web research — tone and brand only.** If the operator gave links in step 1, or a website/social page is easy to find from the business name and location, check it for two things only: brand tone (formal/casual/playful) and brand colour. Do not extract or record business facts (services, hours, pricing, history, positioning) — the tenant agent gathers those itself, gradually, in conversation with the owner. Record which pages were checked, for the task report.

   If the operator accepted the tone/colour defaults as-is, and research suggests a clearly better match (a strong brand colour on the site, a distinct voice in the bio), update `brand_tone`/`primary_color`/`secondary_color` before step 2 and surface the change in the confirmation summary. Otherwise leave the operator's answers untouched.
1.2. Using the collected business type and description, generate the following for this specific business (not a predefined category), by cold generation from the interview answers and any step 1.1 tone/colour findings — do not invent facts that were not collected or found:
   - INDUSTRY_CAPABILITIES_BLOCK: 4-6 bullet lines in the form "- <capability>", describing concretely what this agent helps the owner with, grounded in the actual business. Do not copy wording from any other tenant.
   - INDUSTRY_BRAND_FACTS_BLOCK: 2-5 lines of stable business facts for the Mnemosyne seed — facts that do not change unless the owner makes a deliberate business decision (e.g. founding year, location, brand story, core service categories, facilities), drawn only from what the operator stated in step 1. Do not include anything the owner would change as a routine part of running the business (prices, hours, current offerings) — that belongs in the vault's `Reference/Business Data.md`, which the tenant agent fills in itself over time, never at onboarding.
   - A generated eval file following the exact format used in platform/tenant-hermes/evals/_fixed-safety-v1.yaml (top-level eval_profile, version, purpose, run_mode, checks list; each check has a name, match_type, prompt, and either expected.must_include/must_not_include for match_type: literal, or judge_for for match_type: semantic). Generate 2-4 checks specific to this business. Prefer match_type: literal checks here where possible, because unlike the fixed file's generic categories, generated checks can reference this specific tenant's actual known facts. Only use match_type: semantic for checks where no specific known literal fact applies (e.g., general tone judgments). Do not add a file_location field to generated tenant-specific factual checks unless the check is deliberately verifying file creation; most generated checks should rely on expected.must_include and expected.must_not_include.
   - TENANT_POLICY_RULES: if the operator gave tenant-specific access restrictions in step 1, generate one or more rules in the same shape as a platform-policy.yaml rule (id, category, agent_instruction, eval_checks) — see the example rules in `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template`. Each rule must only narrow behavior, never widen past a platform-policy.yaml rule. If the operator gave no restrictions, this is an empty list — that is the common case, not an error.
   Show the generated INDUSTRY_CAPABILITIES_BLOCK, INDUSTRY_BRAND_FACTS_BLOCK, generated eval checks, and TENANT_POLICY_RULES to the operator as part of the confirmation summary in step 2. Do not write any files yet.
2. Show a full confirmation summary and ask: "Proceed with onboarding? (y/n)"
3. Generate tenant ID as a lowercase slug from business name (spaces → hyphens, strip non-alphanumeric except hyphens, trim leading/trailing hyphens). **Check for collisions before creating any files:**
   ```bash
   grep -q "id: {tenant-id}" /opt/aaas/platform/tenants.yaml \
     && echo "COLLISION: tenant ID already in tenants.yaml" \
     || echo "OK: slug is available in registry"
   [ -d /opt/aaas/tenants/{tenant-id} ] \
     && echo "COLLISION: tenant directory already exists" \
     || echo "OK: directory is free"
   ```
   If either check shows a collision, stop and ask the operator to provide a disambiguating suffix (e.g. `happy-paws-kl` vs `happy-paws-pj`). Do not create any files until the slug is confirmed unique.
4. Create tenant directories under `/opt/aaas/tenants/{tenant-id}/`: `memories`, `skills`, `files/assets`, `files/uploads`, `files/generated`, `vault`.
4.1. **Scaffold the tenant's knowledge vault, empty.** This is a separate
   system from Mnemosyne — see the explanation in `SOUL.md` (rendered from
   `SOUL.md.template`). Run the deterministic scaffolder now, before step 7's
   ownership repair, so the ownership pass covers it:
   ```bash
   /opt/aaas/platform/scripts/backfill-tenant-vault.sh {tenant-id} "{business-name}"
   ```
   `backfill-tenant-vault.sh` copies `vault-init-tenant.sh` into the tenant
   volume and runs it there; you should not need to call
   `vault-init-tenant.sh` directly during onboarding. This creates `/opt/aaas/tenants/{tenant-id}/vault/` with `Customers/`,
   `Suppliers/`, `Recurring/`, `Reference/` folders (including an empty,
   owner-editable `Reference/Business Data.md` stub for current prices, hours,
   and menu), a minimal `.obsidian/` config, and a `README.md` written from
   the actual business name. No facts are pre-written — the vault holds
   nothing until the tenant agent learns it from the owner directly, over
   time, through normal conversation. There is no separate `business-data.md`
   file or `files/assets/business-data.md` path any more; operational facts
   live in the vault like everything else.

   If the operator gave a business description or links in step 1, write
   them into `Reference/Onboarding Notes.md` as raw, unconfirmed source
   material — not as facts the agent can state to a customer:
   ```
   ---
   type: reference
   status: unconfirmed
   created_utc: "{ISO-8601 timestamp}"
   ---
   # Onboarding Notes

   Operator's description: "{business description from step 1}"
   Links given: {links from step 1, or "none"}

   This note is raw source material from onboarding, not a confirmed fact.
   Before treating anything here as settled, check it with the owner in
   conversation — see SOUL.md's guidance on this file.
   ```
   Skip this file entirely if the operator gave no description beyond the
   business type already in `SOUL.md`, and no links.

   The tenant agent itself maintains this vault at runtime — the admin agent's
   job here is only to scaffold it once, empty (plus the optional raw
   `Onboarding Notes.md` above).
5. Render templates into `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `memories/MEMORY.md`, `memories/USER.md`, `harness.yaml`, `ACCEPTANCE.md`, and `tenant-policy.yaml`. Use `/opt/aaas/platform/harness/tenant-harness.yaml.template` for the manifest, `/opt/aaas/platform/harness/ACCEPTANCE.md.template` for acceptance, and `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template` for the tenant policy file — fill in `{{TENANT_ID}}` and `{{BUSINESS_NAME}}`, and add the `rules:` list generated in step 1.2 (empty list if the operator gave no restrictions). Keep `home_chat_id: ""` in `config.yaml` as shipped; Telegram routing is restricted by `TELEGRAM_ALLOWED_USERS` in `.env`. Fill in `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, and `TELEGRAM_HOME_CHANNEL` (from the home-channel choice made in step 1) directly in `.env` during this render, from the owner interview in step 1 — this has to be a plain file write, not a `hermes config set` call: the tenant container doesn't exist yet at this point, and `hermes`/`gateway` only ever live inside the container image (`/opt/hermes/.venv`, read-only — see `platform/docker/Dockerfile`), never on the host for tenants the way they do for admin Hermes (which is host-installed, see setup-admin-hermes.md). `tenant-hermes/skills/configure-telegram-channel-tenant.md` applies once a tenant's gateway is already running (e.g. rotating a live tenant's token later via `docker exec`), not to this first write. Substitute `{{INDUSTRY_CAPABILITIES_BLOCK}}` into `SOUL.md` and `{{INDUSTRY_BRAND_FACTS_BLOCK}}` into `memories/MEMORY.md` using the stable facts generated and confirmed in step 1.2. Write the generated eval checks from step 1.2 to `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml` using the same YAML structure as `_fixed-safety-v1.yaml` (top-level `eval_profile`, `version`, `purpose`, `run_mode`, `checks` list), with `eval_profile` set to `{tenant-id}-v1`. If a fallback provider was collected in step 1, add a top-level `fallback_providers:` list to `config.yaml` with one entry (`provider` and `model`, matching `tenant-hermes/config.yaml.template`'s commented example) — never write the fallback API key into `config.yaml`, it is scrubbed the same way as the primary key in step 6.3. If no fallback provider was collected, leave the `fallback_providers` block commented out exactly as shipped in the template.
5.1. **Render platform and tenant policy into `SOUL.md`.** Read `/opt/aaas/platform/policy/platform-policy.yaml` and the `tenant-policy.yaml` just rendered in step 5. Render each rule's `agent_instruction` as a bullet point under the appropriate section header, inside the `<!-- BEGIN PLATFORM RULES -->`/`<!-- END PLATFORM RULES -->` and `<!-- BEGIN TENANT RULES -->`/`<!-- END TENANT RULES -->` marker comments already present in `SOUL.md.template`. Copy `agent_instruction` verbatim — do not paraphrase. If `tenant-policy.yaml` has an empty `rules:` list, the tenant rules block is correctly empty (markers present, no bullets); this is not an error.
6. Verify `config.yaml` contains `memory.provider: mnemosyne`, `memory_enabled: false`, `user_profile_enabled: false`, and no secrets. If a fallback provider was collected in step 1, also verify `config.yaml` contains a top-level `fallback_providers:` list with the collected `provider` and `model` (and no API key); if no fallback provider was collected, verify the block is still commented out, not silently added. Verify `.env` contains the selected provider API key env var, `TELEGRAM_ALLOWED_USERS` as comma-separated numeric IDs, `TELEGRAM_HOME_CHANNEL` as a single numeric ID present in that list, and `MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data`. Verify `SOUL.md` still contains, unchanged, every fixed conduct line from `platform/tenant-hermes/SOUL.md.template` (the "try to work it out yourself," "always save generated content," "always store owner-uploaded files," and "use `tenant-install.sh`" lines), the `BEGIN/END PLATFORM RULES` and `BEGIN/END TENANT RULES` marker blocks each containing the rendered `agent_instruction` bullets from step 5.1, and that generation only filled in `{{INDUSTRY_CAPABILITIES_BLOCK}}` and the two policy marker blocks without altering any other line.
6.1. Validate the rendered tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
6.2. Copy all tenant runtime scripts into the tenant volume using the deterministic install script:
```bash
   /opt/aaas/platform/scripts/install-tenant-scripts.sh {tenant-id}
```
   This installs `skill-verify.sh`, `tenant-install.sh`, `reconcile-plugins.sh`,
   `tenant-entrypoint.sh`, and `seed-mnemosyne.py` into
   `/opt/aaas/tenants/{tenant-id}/scripts/`, each with `chmod +x`. Idempotent —
   already-current files are skipped. Adding a new runtime script in the future
   only requires updating `install-tenant-scripts.sh` in one place.
6.3. **Provision the tenant vault in Agent Vault:**
   Run the deterministic provision script now — after `.env` exists but before
   container start. Pass the provider-specific API key env var name derived
   from the catalog in step 1 (e.g. `ANTHROPIC_API_KEY`) — the script uses
   this exact name to scrub the real key, so it must not be hardcoded or
   guessed.
   ```bash
   /opt/aaas/platform/scripts/provision-tenant-vault.sh \
     {tenant-id} {provider-env-var} {real-api-key}
   ```
   If a fallback provider was collected in step 1, pass both its derived env
   var and key
   as the optional 4th and 5th arguments:
   ```bash
   /opt/aaas/platform/scripts/provision-tenant-vault.sh \
     {tenant-id} {provider-env-var} {real-api-key} \
     {fallback-provider-env-var} {fallback-real-api-key}
   ```
   The script creates `{tenant-id}-vault`, stores the credential, creates the
   isolated network and forwarding sidecar, mints a proxy token, replaces the
   real key in `.env` with the placeholder `routed-via-agent-vault`, and injects
   `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `AGENT_VAULT_TOKEN`, and
   `AGENT_VAULT_VAULT`. It exits non-zero if any step fails, and verifies no real
   key remains in `.env` before returning. The full procedure is documented in
   `provision-tenant-vault.md` for reference.
   After this step, `.env` must contain no real LLM API key — the script's own
   step 6 checks confirm this; a non-zero exit means do not proceed.
6.4. **Copy the tenant-side admin contact skill and credentials:**
```bash
   cp /opt/aaas/platform/tenant-hermes/skills/tenant-contact-admin.md /opt/aaas/tenants/{tenant-id}/skills/tenant-contact-admin.md
```
   The tenant agent loads this from `/opt/data/skills/tenant-contact-admin.md`
   inside the container, same pattern as `skill-verify.sh` above.
   Write into this tenant's `.env`:
   - `ADMIN_HERMES_API_KEY={value of API_SERVER_KEY from /opt/aaas/platform/admin/.env}`
   `ADMIN_HERMES_API_URL` is already correct from the template and needs no
   per-tenant change. This call reaches admin Hermes's own API server
   (`127.0.0.1:8642`, see step 8 below); the tenant does not run an API
   server of its own.
7. Set tenant volume ownership and host-side read access before starting the container:
   ```bash
   /opt/aaas/platform/scripts/repair-tenant-ownership.sh {tenant-id}
   ```
   This runs `sudo chown -R 10000:10000` (so the Hermes container user, UID 10000,
   can write mounted `/opt/data` paths) and `sudo chmod -R go+rX` (so the
   `docker compose` CLI, run as the operator user, can still read `.env` and other
   tenant files). Both must be recursive — subdirectories the tenant container
   creates at runtime inherit a restrictive default umask and would otherwise
   become unreadable to the host operator. Re-run this script any time
   `harness/check-tenant.sh` reports `tenant_volume_host_readable` as FAIL.
8. Add this tenant's service block to `/opt/aaas/platform/docker/docker-compose.yaml` using the deterministic script — do not write the YAML by hand:
   ```bash
   /opt/aaas/platform/scripts/add-tenant-compose-service.sh {tenant-id}
   ```
   The script appends the complete service block (image, command, `restart: unless-stopped`, mounts, env_file, resource limits (`mem_limit: 1g`, `cpus: "1.0"`), network, healthcheck, watchdog labels) and the required `external: true` network declaration, all with the exact field values the harness and watchdog expect. If the script prints `SKIP` (service already present), stop and confirm with the operator before proceeding — do not re-run or edit the existing block without operator approval.
9. Start only this tenant: `docker compose up -d hermes_{tenant-id}`.
10. **Verify container outbound connectivity** (critical for Telegram and external APIs):
    - Wait 5 seconds for container to stabilize
    - Ping Telegram API: `docker exec hermes_{tenant-id} ping -c 2 -W 3 api.telegram.org`
    - Curl Telegram API HTTPS endpoint: `docker exec hermes_{tenant-id} curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://api.telegram.org && echo`
    - Retest ping/curl if rules were added.
11. Verify with `docker ps` and `docker logs hermes_{tenant-id} --tail 20`.
12. Install/activate the Mnemosyne Hermes plugin inside the tenant volume, then restart only this tenant. All three commands must pin `HERMES_HOME=/opt/data` — this is the same activation operation split across three calls, and it must target the persistent tenant volume every time, not just on the first call, or the resulting activation state may not survive the container recreate on the last line:
   `docker exec -e HERMES_HOME=/opt/data hermes_{tenant-id} mnemosyne-hermes install`
   `docker exec -e HERMES_HOME=/opt/data hermes_{tenant-id} hermes config set memory.provider mnemosyne`
   `docker exec -e HERMES_HOME=/opt/data hermes_{tenant-id} hermes memory setup`
   `docker compose up --force-recreate --no-deps -d hermes_{tenant-id}`
13. Seed Mnemosyne with `memories/MEMORY.md` and `memories/USER.md`, one fact per memory, via the SDK-based seed script (runs inside the container, as the tenant process — no `sudo cat`, no shell string-piping, `scope="global"` so seeded facts are visible outside the seeding process's own session):
   `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/MEMORY.md fact`
   `docker exec hermes_{tenant-id} python3 /opt/data/scripts/seed-mnemosyne.py /opt/data/memories/USER.md preference`
   Each call exits non-zero if any individual fact fails to store — treat a non-zero exit as a failed seed, not a partial success. Verify with `docker exec hermes_{tenant-id} hermes memory status`, `docker exec hermes_{tenant-id} hermes mnemosyne stats --global`, and `docker exec hermes_{tenant-id} hermes mnemosyne inspect "{business-name}"`. To manually store a single fact, use `docker exec hermes_{tenant-id} hermes mnemosyne store`. If `hermes mnemosyne` is unavailable, try the documented fallback `hermes hermes-mnemosyne`.
   Note: the knowledge vault at `/home/hermes/vault/` is a separate system from Mnemosyne: scaffolded empty in step 4.1 (plus an optional unconfirmed `Onboarding Notes.md`), maintained entirely by the tenant agent at runtime, and never seeded into Mnemosyne. It holds current operational facts too (`Reference/Business Data.md`) — there is no separate `business-data.md` file any more. The tenant agent builds the vault up from real conversation with the owner, gradually, starting after the welcome message in step 17 — never all at once.
14. Add or update the tenant entry in `/opt/aaas/platform/tenants.yaml`.
15. Run the deterministic tenant harness check:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   The script auto-detects tenant file permission denial after UID `10000` ownership is applied and re-runs itself with `sudo` when available.
   If it fails, fix the failed checks before completion when possible. If a warning or failure is caused by an external precondition such as the owner not starting the Telegram bot, record it clearly in `ACCEPTANCE.md` and the task report.
16. Run or operator-assist BOTH eval profiles once the tenant container is running:
   - The fixed profile: `/opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml` (mandatory for every tenant, every onboarding, no exceptions)
   - The generated profile for this tenant: `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml`
   Once the tenant container is running, run `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} {path-to-eval-file}` against both profiles for automated PASS/FAIL results on `match_type: literal` checks (this runs prompts inside the container via `hermes -z`, not over Telegram); the script will print `SKIP` for `match_type: semantic` checks, which still require the operator or admin agent to read the actual reply against that check's `judge_for` field. Fall back to fully manual review only if `eval-runner.sh` reports a missing dependency or the container is not running (exit code 2). At minimum, verify brand recall, confirmation before posting, confirmation before deleting, generated/upload folder behavior, owner-friendly language, no cross-tenant memory leakage, and the tenant's own generated industry-specific checks. Record results from both files in `ACCEPTANCE.md`.
   **Do not proceed to the welcome message below until both eval profiles pass (or any failures are explicitly accepted by the operator).** Sending a welcome message before eval verification sets a false expectation that the bot is fully ready.
17. Send the welcome message through the tenant's Telegram bot to every numeric ID in `TELEGRAM_ALLOWED_USERS`. This only succeeds for users who have already opened the bot and sent `/start`; report Telegram `400 Bad Request: chat not found` or `403 Forbidden` as "user must start the bot first":
   `curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="{user-id}" --data-urlencode text="{welcome-message}"`

   Frame the agent as new to the business, not pre-loaded with it: it introduces itself, says it's ready to learn, and will check with the owner before assuming anything. If links were given in step 1, the message says it will take a look at them itself and confirm what it finds — it does not claim to already know the business.
18. Update `/opt/aaas/tenants/{tenant-id}/harness.yaml` with status, last verification timestamp, and verification notes if your editor/tooling can do so safely.
19. Report tenant ID, container status, outbound connectivity test results (ping/curl), harness check summary, tenant eval results, Telegram bot link, Mnemosyne activation/seed status, knowledge vault scaffold status (empty, `Reference/Business Data.md` stub present, plus whether an unconfirmed Onboarding Notes.md was written), tenant-policy.yaml rules generated (or none) and confirmation that both BEGIN/END policy marker blocks rendered in SOUL.md, isolated tenant network created and Agent Vault joined to it, welcome message delivery status per user ID, registry update status, tone/brand sources checked in step 1.1, and fallback LLM provider/model configured (or declined).