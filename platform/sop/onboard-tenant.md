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

   **Design principle:** Most fields have sensible defaults. Present each default inline so the operator can accept it with a single word or skip past it — they only need to type when the default is wrong. The agent's personality and capabilities can always be tuned later; getting the bot running fast is the priority.

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
   | vertical_details | *(derived from business type in step 1.1 web research)* |

   **Never ask the operator for the provider-specific API key env var name — that is always derived, not collected.** Accept the LLM provider/model in whatever form the operator gives it (`provider/model`, e.g. `openrouter/google/gemini-2.0-flash-001`; or separate `provider =` / `model =` answers), split out the Provider ID, and look it up in `/opt/aaas/platform/reference/llm-provider-catalog.md` to get both the hostname (needed later in `provision-tenant-vault.md` step 2) and the env var name (via the catalog's deterministic derivation rule). Only fall back to asking the operator a follow-up question if the named provider isn't in the catalog (ask for its API hostname only, never the env var name — see the catalog's "Provider not in this table" section) or if it falls under the catalog's Exceptions section (OAuth-only or multi-credential providers), in which case follow that section's escalation guidance instead of proceeding. Same rule applies to the optional fallback provider if one is collected.
1.1. **Web research augmentation:** After collecting the operator's answers, proactively search the business website, public review/blog pages, Instagram bios, and Google Business snippets to fill gaps and validate facts. Do this even when the operator has answered every question — website copy often surfaces richer vertical detail than interview answers alone. If a social page blocks unauthenticated access, use the above sources as alternates. Record which sources were used; include them in the final task report.

   **Using research to fill accepted defaults:** If the operator accepted defaults without customising tone, colors, or vertical_details, use web research findings to improve on the defaults before proceeding — e.g. if the business website uses a strong brand colour, prefer that over #2563EB; if their social bio signals a distinct voice, reflect it in brand_tone. Update the working values silently and surface the changes in the step 2 confirmation summary so the operator can see what was inferred.
1.15. **Business intelligence sub-agent:** Run the research sub-agent to synthesise the interview answers and web research into richer, structured context. This replaces cold LLM generation for the capability and brand blocks in step 1.2, and produces the vault seed notes written in step 4.2.

   Assemble the context block from step 1 answers and step 1.1 research text, then run:
   ```bash
   python3 /opt/aaas/platform/scripts/run-business-research-subagent.py \
     --tenant-id    "{tenant-id-slug}" \
     --output-file  "/tmp/aaas-research-{tenant-id-slug}.json" \
     <<'CONTEXT'
   {
     "interview": {
       "business_name": "...",
       "business_type": "...",
       "location": "...",
       "brand_tone": "...",
       "owner_name": "...",
       "language": "...",
       "communication_style": "...",
       "timezone": "...",
       "vertical_details": "...",
       "primary_color": "...",
       "secondary_color": "..."
     },
     "web_research": "...paste step 1.1 research text here, or empty string if nothing found..."
   }
   CONTEXT
   ```

   Read the skill file for full usage details and fallback handling:
   `/opt/aaas/platform/skills/research-tenant-business.md`

   After the script exits 0, read the output:
   ```bash
   cat /tmp/aaas-research-{tenant-id-slug}.json
   ```

   Extract and hold for the steps that consume each field:
   - `vertical_capabilities_block`  → step 1.2 (replaces cold generation)
   - `vertical_brand_facts_block`   → step 1.2 (replaces cold generation)
   - `business_data_context_section` → step 4.1 (appended to business-data.md)
   - `vault_seed_notes`             → step 4.2 (written into scaffolded vault)
   - `research_sources_used`        → step 19 (task report)
   - `confidence`                   → surface to operator in step 2 confirmation

   **If the script fails** (non-zero exit, JSON parse error, or missing output file):
   Log the error, note it in the task report, and continue to step 1.2 using
   cold generation as before. The sub-agent is an enhancement, not a hard gate.
   Do not surface the raw error to the operator — summarise it as "business
   intelligence sub-agent unavailable; using generated context instead."

   **If the failure mentions "response looks truncated"** (the script's
   heuristic for JSON that fails to parse and doesn't end in `}`/`]` — it can
   no longer check a raw API `stop_reason` now that generation runs through
   `hermes -z`, whose output is plain text): a sidecar file
   `/tmp/aaas-research-{tenant-id-slug}.json.raw` was written containing the
   partial output. Before continuing:
   1. Read it: `cat /tmp/aaas-research-{tenant-id-slug}.json.raw`
   2. Note in the task report roughly how far generation got (e.g. "cut off
      partway through vault_seed_notes, capability and brand-fact arrays were
      complete") — this is what tells you later whether truncation is a
      one-off or systemic enough to warrant raising the admin agent's own
      output-length config (there is no separate `SUBAGENT_MAX_TOKENS` any
      more — the sub-agent uses the admin agent's own model settings).
   3. Delete the sidecar immediately after noting it:
      `rm -f /tmp/aaas-research-{tenant-id-slug}.json.raw`
   This file exists only for this one diagnostic read — it is never
   operator-facing, is not consumed by any later step, and contains raw
   interview/research content, so it should not persist on the host past this
   point. Do not wait for step 19 cleanup to remove it.

   **If confidence is `low`:** Add to the step 2 confirmation summary:
   "Note: Limited public information was found for this business. The generated
   context is based mainly on your interview answers. You can provide a website
   URL or Google Business link after onboarding to let the agent update its
   reference notes."

1.2. Using the collected business type and details, generate the following for this specific business (not a predefined category):
   - VERTICAL_CAPABILITIES_BLOCK: 4-6 bullet lines in the form "- <capability>", describing concretely what this agent helps the owner with, grounded in the actual business. **Prefer the `vertical_capabilities_block` array from the step 1.15 sub-agent output if available** — join the array items as newline-separated lines. Fall back to cold generation only if the sub-agent was unavailable. Do not copy wording from any other tenant.
   - VERTICAL_BRAND_FACTS_BLOCK: 2-5 lines of stable business facts for the Mnemosyne seed — facts that do not change unless the owner makes a deliberate business decision (e.g. founding year, location, brand story, core service categories, facilities). Do not include operational details here. **Prefer the `vertical_brand_facts_block` array from the step 1.15 sub-agent output if available** — join as newline-separated lines. Fall back to cold generation only if the sub-agent was unavailable. Do not invent facts that were not collected or found.
   - OPERATIONAL_DETAILS: a separate list of facts that belong in `business-data.md`, not in `MEMORY.md`. Apply this classification rule to every collected fact:

     Classification rule: Can the owner change this as a routine part of running the business, without changing what the business fundamentally is? If yes → operational. If no → stable.

     Stable examples (cross-vertical): founding year, legal name, location, brand story, owner name, core service categories that define the business, facilities that are part of the premises.

     Operational examples (cross-vertical): anything with a price or rate, anything described as a current or available offering, anything with a season or expiry, anything the owner would update on a notice board or menu board without contacting an admin.

     When a fact is ambiguous, classify it as operational — it is safer for it to live in the owner-editable file than to go stale in Mnemosyne.
   - A generated eval file following the exact format used in platform/tenant-hermes/evals/_fixed-safety-v1.yaml (top-level eval_profile, version, purpose, run_mode, checks list; each check has a name, match_type, prompt, and either expected.must_include/must_not_include for match_type: literal, or judge_for for match_type: semantic). Generate 2-4 checks specific to this business. Prefer match_type: literal checks here where possible, because unlike the fixed file's generic categories, generated checks can reference this specific tenant's actual known facts. Only use match_type: semantic for checks where no specific known literal fact applies (e.g., general tone judgments). Do not add a file_location field to generated tenant-specific factual checks unless the check is deliberately verifying file creation; most generated checks should rely on expected.must_include and expected.must_not_include.
   - TENANT_POLICY_RULES: if the operator gave tenant-specific access restrictions in step 1, generate one or more rules in the same shape as a platform-policy.yaml rule (id, category, agent_instruction, eval_checks) — see the example rules in `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template`. Each rule must only narrow behavior, never widen past a platform-policy.yaml rule. If the operator gave no restrictions, this is an empty list — that is the common case, not an error.
   Show the generated VERTICAL_CAPABILITIES_BLOCK, VERTICAL_BRAND_FACTS_BLOCK, OPERATIONAL_DETAILS, generated eval checks, and TENANT_POLICY_RULES to the operator as part of the confirmation summary in step 2. Do not write any files yet.
2. Show a full confirmation summary and ask: "Proceed with onboarding? (y/n)"
3. Generate tenant ID as a lowercase slug from business name.
4. Create tenant directories under `/opt/aaas/tenants/{tenant-id}/`: `memories`, `skills`, `files/assets`, `files/uploads`, `files/generated`, `vault`.
4.1. **Create `business-data.md`** at `/opt/aaas/tenants/{tenant-id}/files/assets/business-data.md` now, before step 7's `chown -R`, so the ownership pass covers it. Write the file in two sections:

   **Section 1 — Operational details** (owner-editable, changes frequently):
   If OPERATIONAL_DETAILS were collected, write them here. If none, write a stub.
   ```
   # Business Data — owner-editable
   # Last updated: {YYYY-MM-DD}
   # This file holds operational details for this business.
   # The assistant checks it before answering questions about them.
   # Update this file whenever details change — no admin action required.

   {operational details here, or stub comment if none}
   ```

   **Section 2 — Business context** (set at onboarding, rarely changes):
   If the step 1.15 sub-agent produced a `business_data_context_section` array,
   append it as a second section after a blank line:
   ```
   ## Assistant Context
   # Set at onboarding. Edit only if this information becomes inaccurate.
   # The assistant uses this to sound like it knows this business without
   # being asked — do not delete lines unless they are factually wrong.

   {one line per item in business_data_context_section array}
   ```
   If the sub-agent was unavailable, omit section 2 entirely — do not leave a
   placeholder or empty header. The file is complete with section 1 alone.
4.2. **Scaffold the tenant's knowledge vault.** This is a separate system from
   both Mnemosyne and `business-data.md` — see the three-way explanation in
   `SOUL.md` (rendered from `SOUL.md.template`) for what the tenant agent is
   told about each. Run the deterministic scaffolder now, before step 7's
   ownership repair, so the ownership pass covers it:
   ```bash
   /opt/aaas/platform/scripts/backfill-tenant-vault.sh {tenant-id} "{business-name}"
   ```
   This calls `vault-init-tenant.sh` to create `/opt/aaas/tenants/{tenant-id}/vault/` with `Customers/`,
   `Suppliers/`, `Recurring/`, `Reference/` folders, a minimal `.obsidian/`
   config so it opens cleanly in the Obsidian app, and a `README.md` written
   from the actual business name (not a template placeholder left unfilled).

   **If the step 1.15 sub-agent succeeded**, seed the vault with the research
   notes it produced. Run the seed script on the host (not inside the container
   — the vault is a host-mounted volume):
   ```bash
   VAULT_DIR="/opt/aaas/tenants/{tenant-id}/vault" \
     python3 /opt/aaas/platform/tenant-hermes/scripts/seed-vault-context.py \
       --research-file "/tmp/aaas-research-{tenant-id}.json" \
       --vault-dir     "/opt/aaas/tenants/{tenant-id}/vault"
   ```
   Expected output: three `PASS` lines for the seed notes written into
   `Reference/Business Overview.md`, `Reference/Vertical Playbook.md`, and
   `Recurring/Patterns to Watch.md`. A `SKIP` line means a note already existed
   (safe — idempotent). A `FAIL` line means a note could not be written — log
   the reason in the task report but do not abort onboarding; the vault is still
   functional without seed notes.

   If the sub-agent was unavailable, skip this seed step — the vault starts
   with its README and empty section folders as before, and the tenant agent
   will populate it at runtime. Note the skip in the task report.

   The tenant agent itself maintains this vault at runtime — the admin agent's
   job here is only to scaffold it once and seed it with initial context.
5. Render templates into `config.yaml`, `.env`, `.env.template`, `SOUL.md`, `memories/MEMORY.md`, `memories/USER.md`, `harness.yaml`, `ACCEPTANCE.md`, and `tenant-policy.yaml`. Use `/opt/aaas/platform/harness/tenant-harness.yaml.template` for the manifest, `/opt/aaas/platform/harness/ACCEPTANCE.md.template` for acceptance, and `/opt/aaas/platform/tenant-hermes/policy/tenant-policy.yaml.template` for the tenant policy file — fill in `{{TENANT_ID}}` and `{{BUSINESS_NAME}}`, and add the `rules:` list generated in step 1.2 (empty list if the operator gave no restrictions). Keep `home_chat_id: ""` in `config.yaml`; Telegram routing is restricted by `TELEGRAM_ALLOWED_USERS` in `.env`. Substitute `{{VERTICAL_CAPABILITIES_BLOCK}}` into `SOUL.md` and `{{VERTICAL_BRAND_FACTS_BLOCK}}` into `memories/MEMORY.md` using the stable facts generated and confirmed in step 1.2. Operational details classified in step 1.2 must not appear in `MEMORY.md`. Write the generated eval checks from step 1.2 to `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml` using the same YAML structure as `_fixed-safety-v1.yaml` (top-level `eval_profile`, `version`, `purpose`, `run_mode`, `checks` list), with `eval_profile` set to `{tenant-id}-v1`. If a fallback provider was collected in step 1, add a top-level `fallback_providers:` list to `config.yaml` with one entry (`provider` and `model`, matching `tenant-hermes/config.yaml.template`'s commented example) — never write the fallback API key into `config.yaml`, it is scrubbed the same way as the primary key in step 6.3. If no fallback provider was collected, leave the `fallback_providers` block commented out exactly as shipped in the template.
5.1. **Render platform and tenant policy into `SOUL.md`.** Read `/opt/aaas/platform/policy/platform-policy.yaml` and the `tenant-policy.yaml` just rendered in step 5. Render each rule's `agent_instruction` as a bullet point under the appropriate section header, inside the `<!-- BEGIN PLATFORM RULES -->`/`<!-- END PLATFORM RULES -->` and `<!-- BEGIN TENANT RULES -->`/`<!-- END TENANT RULES -->` marker comments already present in `SOUL.md.template`. Copy `agent_instruction` verbatim — do not paraphrase. If `tenant-policy.yaml` has an empty `rules:` list, the tenant rules block is correctly empty (markers present, no bullets); this is not an error.
6. Verify `config.yaml` contains `memory.provider: mnemosyne`, `memory_enabled: false`, `user_profile_enabled: false`, and no secrets. If a fallback provider was collected in step 1, also verify `config.yaml` contains a top-level `fallback_providers:` list with the collected `provider` and `model` (and no API key); if no fallback provider was collected, verify the block is still commented out, not silently added. Verify `.env` contains the selected provider API key env var, `TELEGRAM_ALLOWED_USERS` as comma-separated numeric IDs, and `MNEMOSYNE_DATA_DIR=/opt/data/mnemosyne/data`. Verify `SOUL.md` still contains, unchanged, every fixed conduct line from `platform/tenant-hermes/SOUL.md.template` (the "try to work it out yourself," "always save generated content," "always store owner-uploaded files," and "use `tenant-install.sh`" lines), the `BEGIN/END PLATFORM RULES` and `BEGIN/END TENANT RULES` marker blocks each containing the rendered `agent_instruction` bullets from step 5.1, and that generation only filled in `{{VERTICAL_CAPABILITIES_BLOCK}}` and the two policy marker blocks without altering any other line.
6.1. Validate the rendered tenant config:
   `/opt/aaas/platform/scripts/validate-tenant-config.sh {tenant-id}`
6.2. Copy all tenant runtime scripts into the tenant volume using the deterministic install script:
```bash
   /opt/aaas/platform/scripts/install-tenant-scripts.sh {tenant-id}
```
   This installs `skill-verify.sh`, `tenant-install.sh`, `reconcile-plugins.sh`,
   `tenant-entrypoint.sh`, `seed-mnemosyne.py`, and `seed-vault-context.py` into
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
   Note: `business-data.md` is not seeded into Mnemosyne — it is read directly by the tenant agent at runtime from `/home/hermes/files/assets/business-data.md`. The knowledge vault at `/home/hermes/vault/` is a third, separate system: scaffolded and seed-noted in step 4.2, maintained by the tenant agent itself at runtime, and never seeded into Mnemosyne. If the step 1.15 sub-agent succeeded, the vault already contains `Reference/Business Overview.md`, `Reference/Vertical Playbook.md`, and `Recurring/Patterns to Watch.md` — the tenant agent can query these from day one. The tenant agent will continue to add and update notes at runtime as it learns new durable facts.
14. Add or update the tenant entry in `/opt/aaas/platform/tenants.yaml`.
15. Send the welcome message through the tenant's Telegram bot to every numeric ID in `TELEGRAM_ALLOWED_USERS`. This only succeeds for users who have already opened the bot and sent `/start`; report Telegram `400 Bad Request: chat not found` or `403 Forbidden` as "user must start the bot first":
   `curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="{user-id}" --data-urlencode text="{welcome-message}"`
16. Run the deterministic tenant harness check:
   `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`
   The script auto-detects tenant file permission denial after UID `10000` ownership is applied and re-runs itself with `sudo` when available.
   If it fails, fix the failed checks before completion when possible. If a warning or failure is caused by an external precondition such as the owner not starting the Telegram bot, record it clearly in `ACCEPTANCE.md` and the task report.
17. Run or operator-assist BOTH eval profiles once the tenant container is running:
   - The fixed profile: `/opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml` (mandatory for every tenant, every onboarding, no exceptions)
   - The generated profile for this tenant: `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml`
   Once the tenant container is running, run `/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} {path-to-eval-file}` against both profiles for automated PASS/FAIL results on `match_type: literal` checks (this runs prompts inside the container via `hermes -z`, not over Telegram); the script will print `SKIP` for `match_type: semantic` checks, which still require the operator or admin agent to read the actual reply against that check's `judge_for` field. Fall back to fully manual review only if `eval-runner.sh` reports a missing dependency or the container is not running (exit code 2). At minimum, verify brand recall, confirmation before posting, confirmation before deleting, generated/upload folder behavior, owner-friendly language, no cross-tenant memory leakage, and the tenant's own generated vertical-specific checks. Record results from both files in `ACCEPTANCE.md`.
18. Update `/opt/aaas/tenants/{tenant-id}/harness.yaml` with status, last verification timestamp, and verification notes if your editor/tooling can do so safely.
19. Report tenant ID, container status, outbound connectivity test results (ping/curl), harness check summary, tenant eval results, Telegram bot link, Mnemosyne activation/seed status, knowledge vault scaffold status and vault seed notes written (or skipped), business intelligence sub-agent status (succeeded/failed/fallback) and confidence level, tenant-policy.yaml rules generated (or none) and confirmation that both BEGIN/END policy marker blocks rendered in SOUL.md, isolated tenant network created and Agent Vault joined to it, welcome message delivery status per user ID, registry update status, research sources used (from sub-agent output or step 1.1), fallback LLM provider/model configured (or declined), and whether operational details and assistant context section were written to `files/assets/business-data.md` or a stub was created for future owner use. Remove the temp research file: `rm -f /tmp/aaas-research-{tenant-id}.json /tmp/aaas-research-{tenant-id}.json.raw` (the `.raw` sidecar should already be gone if a truncation was handled at step 1.15 — this is a safety net, not the primary cleanup path).