# Platform Architecture

This document covers how the AaaS Platform is designed: repository and host
layout, the credential security model, the policy framework, task reporting,
the knowledge vault systems, tenant harness/eval verification, and the
watchdog/health-monitoring design. For installation steps, see the
[README](../README.md); for a full step-by-step setup walkthrough see
[platform-setup.md](platform-setup.md).

## Repository Structure

The repo splits cleanly into host-platform assets (operated by you and the admin agent) and tenant-agent assets (templated out per tenant, then copied and run inside each tenant's own Docker container). Everything under `platform/tenant-hermes/` is the tenant agent's own asset tree; everything else under `platform/` is host-side.

```
aaas-platform/
├── README.md, CHANGELOG.md         — intro/getting-started, and the platform setup version history
├── docs/                           — prerequisites, full setup walkthrough, troubleshooting, this file
├── scripts/                        — top-level install scripts (setup-prerequisites.sh, setup-platform.sh, setup.sh)
├── archived-dont-read/             — historical design notes, not current; paths inside are intentionally stale
└── platform/                       — installs to /opt/aaas/platform on the host
    ├── AGENTS.md                   — OpenCode admin agent's own identity + pointer to PLATFORM-REFERENCE.md
    ├── PLATFORM-REFERENCE.md       — shared path quick-reference, rules, workflows (read by both OpenCode and Hermes admin agents; carries no agent identity)
    ├── VERSION                     — platform setup version (see Versioning below)
    ├── admin-hermes/               — HOST: Hermes admin agent's own templates (config/SOUL/USER/MEMORY/env)
    ├── admin/                      — HOST: the admin agent's deployed profile + secrets (rendered from admin-hermes/), locked to the aaas user only
    ├── tenant-hermes/              — TENANT: every asset a tenant agent ships with, copied per-tenant at onboarding
    │   ├── config.yaml.template, env.template, SOUL.md.template, USER.md.template, MEMORY.md.template
    │   ├── policy/                 — tenant-policy.yaml.template (per-tenant operator restrictions)
    │   ├── skills/                 — tenant-contact-admin.md (tenant agent's own skill)
    │   ├── scripts/                — skill-verify.sh, vault-init-tenant.sh (run inside the tenant container or against tenant volumes)
    │   └── evals/                  — tenant agent eval profiles (see below)
    ├── evals/                      — HOST: admin agent's own eval profile (meta-eval-generation-v1.yaml)
    ├── sop/                        — host-run SOPs: onboard/update/troubleshoot/upgrade/offboard a tenant, etc.
    ├── skills/                     — admin agent's own skills (vault management, tenant request handling, …)
    ├── harness/                    — check-tenant.sh + manifest/acceptance templates used to verify a tenant install
    ├── checklists/                 — required-step JSON checklists the admin agent must complete
    ├── policy/                     — platform-policy.yaml, the canonical source of platform-wide safety rules
    ├── scripts/                    — host-side operational scripts (eval-runner.sh, watchdog, vault-init.sh, …)
    ├── docker/                     — Dockerfile for the tenant image
    ├── incidents/                  — incident playbooks
    ├── reports/                    — task reports written by the admin agent during operations
    └── logs/                       — operational logs: watchdog activity, Hermes admin process stdout (rotated, kept separate from reports/ so report indexing/analysis tooling never scans them)
```

Outside `platform/`, at the top level of `/opt/aaas/`, sit the other runtime
roots: `tenants/` (per-tenant data) and `agent-vault/` (the credential
broker's own container data). The admin agent's Hermes install itself lives
outside `/opt/aaas/` entirely — `~/.local/bin/hermes` and
`~/.hermes/hermes-agent/`, the official per-user installer's own layout,
owned by the same operator account as everything else. Only the rendered
profile and secrets live under the platform tree, at `platform/admin/`
(locked down, `chmod 700`/`.env` at `600`, but no separate identity owns it
— see below).

A few path distinctions worth knowing up front, since they're easy to mix up:

- **`platform/AGENTS.md`** vs **`platform/PLATFORM-REFERENCE.md`**: `AGENTS.md` is read only by the OpenCode admin agent (OpenCode auto-loads this filename by convention) and asserts that agent's identity. `PLATFORM-REFERENCE.md` is read by both the OpenCode admin agent and the Hermes admin agent (via its own `SOUL.md`) and carries no identity claim of its own — this split exists specifically so the Hermes admin agent, an always-on Telegram/API-reachable daemon, is never told "you are the OpenCode admin agent" when loading shared platform knowledge, which previously made the OpenCode-only `upgrade-platform.md` precondition ambiguous for it to evaluate.
- **`platform/tenant-hermes/evals/`** holds the tenant agent's own eval profiles — `_fixed-safety-v1.yaml` (vertical-agnostic safety checks run against every tenant) and `_skill-verification-primitives-v1.yaml` (credential-scanning rules used by `tenant-hermes/scripts/skill-verify.sh` inside the tenant container), plus `generated/{tenant-id}-v1.yaml` per-tenant checks created during onboarding. These are run against a live tenant container.
- **`platform/evals/`** holds only `meta-eval-generation-v1.yaml`, a static synthetic test of the *admin* agent's onboarding generation step. It has nothing to do with any individual tenant and is run manually whenever `PLATFORM-REFERENCE.md` or the admin agent's model changes.
- **`platform/admin-hermes/`** vs **`platform/tenant-hermes/`** mirrors this same host/tenant split for agent templates generally: `admin-hermes/` is the one Hermes admin agent that runs on the host, `tenant-hermes/` is the template every tenant's own Hermes agent is built from.
- **`platform/admin-hermes/`** (templates) vs **`platform/admin/`** (deployed instance) vs **`~/.local/bin/hermes` + `~/.hermes/hermes-agent/`** (the Hermes runtime itself): the templates are upgrade-managed and refreshed by platform upgrades; the deployed profile under `platform/admin/` is rendered from them once and then holds live, operator-specific state (including `.env` secrets) that upgrades only diff-and-ask about, never overwrite; the Hermes install under the operator's own home directory is pure install output with no secrets, managed entirely by the official installer (`hermes update` to upgrade it) and untouched by this platform's own upgrade process.

## Credential Security Model

Tenant containers never hold real LLM API keys. The flow is:

1. **Agent Vault** stores the real key encrypted at rest (AES-256-GCM).
2. During onboarding, the admin agent runs `provision-tenant-vault` which creates a scoped vault, stores the key, and mints a proxy token for the tenant.
3. The tenant `.env` receives `HTTP_PROXY`/`HTTPS_PROXY` pointing at a per-tenant forwarding sidecar (`agent-vault-proxy-{tenant-id}`) that relays only the MITM proxy port through to Agent Vault, with the scoped proxy token embedded as the Basic auth username in the URL (e.g. `http://<token>@agent-vault-proxy-{tenant-id}:14322`) so the openai/httpx SDK sends a `Proxy-Authorization` header on every `CONNECT` request — the proxy rejects unauthenticated connections with 407. `SSL_CERT_FILE` is also set to the system CA bundle so Python's SSL context trusts the Agent Vault MITM CA (the certifi bundle bundled with the SDK does not include it). The LLM key env var is set to the placeholder `routed-via-agent-vault`.
4. When the tenant container makes an outbound LLM API call, Agent Vault intercepts the TLS connection, injects the real key into the `Authorization` header, and forwards the request. The tenant container sees only the proxy token.
5. Traffic that isn't the registered LLM provider is either excluded from the proxy via `NO_PROXY` (Telegram and other non-LLM integrations connect directly, never through the MITM) or, if neither registered nor excluded, rejected — a vault only forwards requests to hosts that have a registered service, and anything without one is denied by default rather than passed through unmanaged. This keeps Agent Vault scoped to brokering the LLM credential, not silently intercepting or permitting everything else the tenant container does.
6. Each tenant runs on its own isolated Docker network (`hermes-{tenant-id}-net`), with only that tenant's container and its forwarding sidecar (`agent-vault-proxy-{tenant-id}`) as members — never a network shared with any other tenant, and never Agent Vault itself. This stops a compromised tenant container from reaching any other tenant's container. Agent Vault's management port (`:14321`) is never reachable from inside any tenant container: the sidecar that joins the tenant network only forwards `:14322` and has no route to `:14321` to forward in the first place, so this holds structurally rather than depending on a host port binding or access-control rule that could later be misconfigured.
7. The only places credential data may ever be persisted for a tenant are `/opt/data/.env` and nothing else. The tenant agent may **append** a single new `KEY=value` line to `.env` — but only after the owner gives explicit confirmation in the same conversation, and immediately followed by a `--force-recreate` so the value takes effect. The agent never edits or removes an existing line (append-only), and the `no_env_disclosure` rule still applies in full: the agent never reveals the value it just wrote. All other persistence targets remain strictly off-limits: Mnemosyne, self-written skills, knowledge vault notes, generated files, and all other files. This is enforced behaviorally by the `no_credential_persistence` platform rule (rendered into every tenant's `SOUL.md`) and mechanically by an automatic credential scan that runs on every self-written skill before it can be trusted (see [Policy Framework](#policy-framework) below).

LLM API keys are managed exclusively inside Agent Vault. To change a tenant's key,
contact the platform operator to update it directly in Agent Vault, or offboard and
re-onboard the tenant using the full onboard-tenant SOP.

Supported LLM providers and their Agent Vault hostnames:

Authoritative source: `platform/reference/llm-provider-catalog.md`. This
table is a convenience excerpt only — do not edit this copy independently of
the catalog.

| Provider         | Hostname            | Env var                  |
|------------------|---------------------|---------------------------|
| OpenRouter       | `openrouter.ai`     | `OPENROUTER_API_KEY`     |
| OpenAI           | `api.openai.com`    | `OPENAI_API_KEY`         |
| Anthropic        | `api.anthropic.com` | `ANTHROPIC_API_KEY`      |
| Nous             | `api.nous.ai`       | `NOUS_API_KEY`           |
| OpenCode Zen     | `opencode.ai`       | `OPENCODE_ZEN_API_KEY`   |
| OpenCode Go      | `opencode.ai`       | `OPENCODE_GO_API_KEY`    |

## Policy Framework

Platform-wide hard rules (the agent never discloses `.env` contents, persists
credentials only to `/opt/data/.env` and only append-only after explicit owner confirmation,
never scans the network, always confirms before an irreversible action, never leaks one
tenant's data to another, always uses owner-friendly language) live in exactly one place:
`platform/policy/platform-policy.yaml`.
Each rule there is a single `agent_instruction` plus its own `eval_checks` — both the
text rendered into every tenant's `SOUL.md` and the automated/judge-assisted checks
that verify the agent actually follows it are generated from this one file, so there
is nothing to keep in sync by hand.

- After editing `platform-policy.yaml`, run `platform/scripts/generate-platform-eval.sh`
  to regenerate `tenant-hermes/evals/_fixed-safety-v1.yaml`, then
  `platform/scripts/validate-platform-rules.sh` to confirm every rule has matching eval
  coverage. Never hand-edit `_fixed-safety-v1.yaml` directly.
- Each tenant additionally has its own `tenant-policy.yaml` for business-specific
  restrictions an operator sets at onboarding (e.g. "only post to these two channels",
  "only query this one database"). Tenant policy is additive-only — it can narrow what
  the agent is allowed to do but can never widen past a platform rule.
- Both files are rendered into the tenant's `SOUL.md` as two marked blocks
  (`<!-- BEGIN/END PLATFORM RULES -->` and `<!-- BEGIN/END TENANT RULES -->`) during
  onboarding and whenever either policy file changes.
- Every self-written tenant skill is scanned for credential-shaped patterns
  (API keys, `password=`/`token=`-style assignments, embedded connection strings)
  before it can be trusted — this runs automatically as part of skill verification,
  independent of whatever the skill's own spec checks for.

## Task Reports

After every SOP task or operational troubleshooting work, the admin agent must write a report before declaring completion.
Use the [write-report](../platform/sop/write-report.md) SOP for detailed guidance.

**Report Locations:**
- Full report: `/opt/aaas/platform/reports/{timestamp}_{sop-or-task-name}_{tenant-or-platform}_{status}.md`
- AI index: `/opt/aaas/platform/reports/INDEX.jsonl` (one JSON object per line, structured for analysis)

**Report Content:**
- Markdown report: Human audit trail with YAML frontmatter (metadata), summary, actions, validation, root cause analysis, issues, and improvement signals
- JSON index: Compact structured record with `sop`, `status`, `tenant_id`, `summary`, `issues`, `improvement_signals`, `next_action`, and other metadata for trend analysis

**Analyze Reports:**
Run `/opt/aaas/platform/scripts/analyze-reports.sh` to query the INDEX for platform improvement opportunities:
```bash
cd /opt/aaas/platform
./scripts/analyze-reports.sh
```

This summarizes issues, improvement signals, partial/failed SOPs, and pending next actions from recent reports without rereading every full Markdown file.

**Important:** Reports must never contain secrets; redact API keys, bot tokens, access tokens, private URLs, and customer private data.

## Platform Knowledge Vault

The platform maintains an [Obsidian](https://obsidian.md)-compatible knowledge vault at `/opt/aaas/platform/vault` — a curated, cross-linked layer of plain Markdown notes that sits on top of the raw task reports. It is the admin agent's own second brain about operating the platform: somewhere a human operator can open in the Obsidian app, browse, search, and follow links between tenants, incidents, and recurring SOP friction, rather than rereading every full report.

It is intentionally separate from three other systems with similar-sounding names:
- **Agent Vault** stores tenant credentials and secrets — never knowledge.
- **Mnemosyne** is each tenant's own in-conversation runtime memory — business-facing, not operator-facing.
- **Each tenant's own knowledge vault** (below) is that tenant's business knowledge, not platform-operations knowledge.

The platform knowledge vault is scaffolded automatically during install/upgrade and is safe to open immediately:

```bash
# Open /opt/aaas/platform/vault as a vault in the Obsidian app
```

The admin agent writes to it following `/opt/aaas/platform/sop/sync-knowledge-vault.md` — typically right after writing a task report for a tenant root cause, an incident, or a recurring SOP friction point. Routine, no-news reports are not mirrored into the vault; it is for durable judgment and cross-links, not a duplicate of `INDEX.jsonl`.

Before troubleshooting a tenant or proposing an SOP change, the admin agent checks the vault first using `/opt/aaas/platform/skills/query-knowledge-vault.md`:

```bash
grep -ril "{keyword}" /opt/aaas/platform/vault --include='*.md'
```

Both `query-knowledge-vault.md` and `sync-knowledge-vault.md` are **admin-agent-only** — they run on the host against `/opt/aaas/platform/vault` and are never available inside a tenant container. They are not the mechanism the tenant agent uses for its own vault; see Tenant Knowledge Vault below.

Vault layout:
- `Tenants/{tenant-id}.md` — one evolving note per tenant
- `Incidents/{timestamp}-{slug}.md` — timestamped write-ups with root cause and fix
- `SOPs/{sop-name}.md` — accumulated commentary and gotchas per SOP (links to, never duplicates, the native SOP file)
- `Platform/{topic}.md` — architecture decisions and platform-wide notes
- `Daily/{YYYY-MM-DD}.md` — optional running log

The vault is additive and never blocks SOP completion: if it is missing or a write fails, the admin agent reports it as a minor follow-up and continues. Like reports, the vault must never contain secrets, API keys, tokens, or customer private data.

## Tenant Knowledge Vault

Each tenant also gets its own, separate Obsidian-compatible knowledge vault at `/opt/aaas/tenants/{tenant-id}/vault`, mounted into the container at `/home/hermes/vault`. This is the tenant agent's own second brain about the business it runs — owner-browsable, owner-editable, and maintained by the tenant agent itself at runtime, not by the admin agent.

A tenant has **two** distinct memory/knowledge systems, each with one job:

| System | Holds | Read pattern |
|---|---|---|
| **Mnemosyne** | in-conversation recall (preferences, recent context) | queried by similarity, mid-conversation |
| **Knowledge vault** (`vault/`) | everything durable: today's prices/menu/hours/availability (`Reference/Business Data.md`) alongside customers, suppliers, recurring patterns, and reference material | linked Markdown notes, browsed/searched, owner-editable |

These do not overlap by design: fleeting conversational context belongs in Mnemosyne, everything durable — including today's operational truth — belongs in the vault. The tenant's `SOUL.md` (rendered from `SOUL.md.template`) carries the exact decision rule the tenant agent follows when it learns a new fact, so this distinction lives with the agent at runtime, not only in platform documentation.

There is no separate `business-data.md` file or `files/assets/business-data.md` path; that was merged into the vault in v0.19.0 (see `CHANGELOG.md`) so operational facts go through the same owner-editable, agent-maintained system as everything else, rather than being a third parallel file with its own rules.

### Vault scaffolding

The vault is scaffolded once during onboarding (`onboard-tenant.md` step 4.1) using `/opt/aaas/platform/tenant-hermes/scripts/vault-init-tenant.sh`, copied into the tenant volume and run against the host-mounted path. It creates `Customers/`, `Suppliers/`, `Recurring/`, and `Reference/` folders (including an empty `Reference/Business Data.md` stub), a minimal `.obsidian/` config, and a `README.md` explaining the vault to the owner. The same script is safe to re-run for tenants onboarded before this feature existed (see `update-tenant.md` and `upgrade-tenants.md`) — it never overwrites existing notes.

The vault starts empty — no pre-written notes, no research step, no synthesis pass, and no operational details collected at onboarding. The tenant agent builds it entirely from real conversation with the owner, gradually, over time — it should never feel to the owner like an interview or a batch data-collection exercise. The welcome message (`onboard-tenant.md` step 17) introduces the agent as new to the business and ready to learn rather than already knowing it.

**Onboarding source material (optional).** If the operator gave a business description or website/social links during onboarding, step 4.1 writes them, verbatim and unmodified, into a single `Reference/Onboarding Notes.md` note marked `status: unconfirmed`. This is a pointer to raw material, not a fact: `SOUL.md` instructs the tenant agent to look at any linked pages itself when it's natural to do so and confirm what it finds with the owner, rather than treating anything in that note as settled, and to fold confirmed details into `Reference/Business Data.md` or another vault note as they're confirmed — with no deadline for doing so. No sub-agent, no separate research pass at onboarding time, and no other vault note is written before the tenant agent's own conversation with the owner produces one.

This replaces the business intelligence sub-agent and vault-seeding pipeline that shipped in earlier versions (`run-business-research-subagent.py`, `seed-vault-context.py`, `research-tenant-business.md` — removed in v0.19.0). That pipeline pre-wrote `Reference/Business Overview.md`, `Reference/Vertical Playbook.md`, and `Recurring/Patterns to Watch.md` from research before the tenant ever spoke to the agent, which conflicted with the vault's own "nothing is pre-seeded, everything comes from real conversation" design — see `CHANGELOG.md` 0.19.0.

### Tenant agent vault usage

The tenant agent has no `platform/skills/`-style loader the way the admin agent does — it only ever reads `SOUL.md` and files it is told to check. So its "search before writing a new note" habit is not a separate skill file; it is written directly into `SOUL.md.template`, backed by a "For the assistant" reference section at the bottom of the generated `vault/README.md` (the same file the owner reads, with the agent-facing part clearly marked so it's easy to skip). The admin-only `query-knowledge-vault.md` skill is unrelated and unreachable from inside a tenant container.

`check-tenant.sh` and `validate-tenant-config.sh` verify the vault exists, is owned by UID 10000, and is mounted into the container; these are part of the standard tenant harness, not a separate check the operator has to remember.

## Tenant Plugin Persistence

The base `nousresearch/hermes-agent` image supports installing a pip package
or standalone binary at runtime, but disables it by default
(`HERMES_DISABLE_LAZY_INSTALLS=1`) because its default install locations sit
outside any mounted volume — anything installed that way vanishes silently on
the next `docker compose up --force-recreate`, with no error pointing at the
cause. `platform/docker/Dockerfile` re-enables the mechanism
(`HERMES_DISABLE_LAZY_INSTALLS=0`) and this platform supplies the piece the
base image doesn't: a supported way to install to the one location that does
persist — the tenant's mounted `/opt/data` volume — and to recover that state
after a recreate.

**How it works:**

1. **`tenant-hermes/scripts/tenant-install.sh`** (copied into every tenant volume
   at onboarding, `onboard-tenant.md` step 6.2.1) is the only supported way for
   the tenant agent to add a pip package or binary at runtime — `SOUL.md.template`
   tells it never to call `pip`/`uv`/`apt` directly or write into `/opt/hermes/`
   (root-owned, read-only, and a live write there can crash the running gateway
   process). It installs pip packages to `/opt/data/lazy-packages` and binaries
   to `/opt/data/.local/bin` — both on the persistent volume — and records every
   install in `/opt/data/installed-plugins.yaml`.
2. **`tenant-hermes/scripts/reconcile-plugins.sh`**, run automatically by
   `tenant-hermes/scripts/tenant-entrypoint.sh` on every container start (before
   `exec gateway run`), reads that manifest and reinstalls anything missing or
   built for a since-superseded Python ABI (tracked per entry as `python_abi`).
   It never blocks startup on failure — a failed reconciliation is logged and
   startup continues, since a missing plugin should degrade one capability, not
   take the tenant offline. Every entry is always attempted regardless of
   earlier failures, but the script's own exit code reflects whether any entry
   failed (`0` = all entries OK or not present; `1` = at least one reinstall
   failed) — `tenant-entrypoint.sh` uses this to write `/opt/data/.reconcile-failed`
   (cleared on the next successful reconcile), which `harness/check-tenant.sh`
   surfaces as `WARN plugin_reconcile_healthy` so degraded plugin state is
   visible without reading container logs.
3. `tenant-install.sh` also supports `remove <name>` and `list`. Removing a pip
   package deletes only the specific files that install added under the shared
   `lazy-packages` directory (tracked per-package as `installed_paths`, since
   `pip`/`uv` have no built-in way to uninstall a single package from a
   `--target` install) — never the whole directory, so removing one tenant's
   package can never delete another package installed alongside it.
4. **`harness/check-tenant.sh`** has a dedicated `tenant_scripts_present` check
   (separate from the generic `skill-verify.sh` checks) confirming all three
   scripts — `tenant-install.sh`, `reconcile-plugins.sh`, `tenant-entrypoint.sh`
   — are present and executable, precisely because a missing script here is a
   silent-data-loss risk on the next recreate, not just a missing file.

**Lifecycle ownership:** the tenant agent owns the decision of what to
install and when to remove it — `SOUL.md.template` tells it to `remove` a
package once it knows the package is no longer needed, since it's the only
party with the context to know that. The admin agent owns the mechanism
(deploying the scripts, understanding the persistence/reconciliation
contract for troubleshooting) but not the cleanup decision: `monitor-health.md`
includes an explicitly opportunistic, non-blocking check where the admin agent
may note an unusually large or stale manifest for a flagged tenant, but is
told not to run `remove` itself, since it lacks the tenant-side context to
know if something still backs a scheduled skill.

**What is never in the manifest:** packages baked into the tenant image at
build time (e.g. `mnemosyne-memory`, `mnemosyne-hermes` — see
`platform/docker/Dockerfile`) are not, and should not be, tracked in
`installed-plugins.yaml`. (`faster-whisper` and `himalaya` were previously
baked in here too — both were removed 2026-07-05; a tenant that genuinely
needs email or speech-to-text now gets it through runtime lazy-install like
any other tenant-specific capability.) That manifest
exists solely for what the tenant agent chose to add at runtime; image-baked
capabilities are identical across every tenant and versioned by the image tag,
not per-tenant state. If a tenant reports a missing capability after a
recreate, `troubleshoot-tenant.md`'s "Tenant-Installed Plugin Missing Or Not
Working" section is the diagnostic entry point.

## Tenant Harness

The platform installs tenant harness assets under `/opt/aaas/platform/harness`,
required SOP checklists under `/opt/aaas/platform/checklists`, and eval assets
under `/opt/aaas/platform/evals`.

Every tenant should have `/opt/aaas/tenants/{tenant-id}/harness.yaml` and
`/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md`. The admin agent uses these files,
plus `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`, to prove that the
tenant gets a brand-aware, private, owner-safe assistant rather than only a
running Docker container.

`check-tenant.sh`'s Agent Vault isolation checks prove both directions: the
management port (`:14321`) must be unreachable from the tenant container via
either the `agent-vault` or `agent-vault-proxy-{tenant-id}` hostname, **and**
the sidecar container itself must be confirmed running (`agent_vault_sidecar_running`)
with its proxy port (`:14322`) actually answering (`agent_vault_sidecar_proxy_port_reachable`).
The not-reachable checks alone can't distinguish a properly isolated sidecar
from a crashed one — both look like a failed connection from inside the
tenant — so the positive liveness checks exist specifically to rule out the
false-PASS case where the sidecar is down and the tenant's LLM calls are
silently failing.

Tenant behavioral validation has two eval layers:

- Fixed safety eval: `/opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml`
- Generated tenant eval: `/opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml`

Run evals once the tenant container is running:

```bash
/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/tenant-hermes/evals/_fixed-safety-v1.yaml
/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/tenant-hermes/evals/generated/{tenant-id}-v1.yaml
```

`eval-runner.sh` runs literal checks inside the tenant container with `hermes -z`.
Semantic checks print `SKIP` by default and require operator or admin-agent review
against the eval file's `judge_for` field.

**Validation and Troubleshooting:**
- Validation: `/opt/aaas/platform/scripts/preflight-check.sh` and `/opt/aaas/platform/scripts/validate-tenant-config.sh` check infrastructure and tenant configuration before major operations
- Troubleshooting: Use `/opt/aaas/platform/sop/troubleshoot-tenant.md` when a tenant needs diagnosis or recovery
- Incident playbooks: `/opt/aaas/platform/incidents/` contains runbooks for common failure scenarios (connectivity, Docker issues, Telegram API changes, backup recovery, Agent Vault failures, etc.)

**Single-Tenant Container Changes:**
After tenant config, secret, or model provider changes, recreate only that tenant's
container so the new state is loaded cleanly:

```bash
cd /opt/aaas/platform/docker
docker compose up --force-recreate --no-deps -d hermes_{tenant-id}
```

Do not use `docker compose restart` for those changes. Do not use broad
`docker compose down` to resolve a single-tenant issue because it affects other
tenants.

**SOP Improvement:**
SOP improvement work should use `/opt/aaas/platform/sop/improve-sop.md`. Native
SOP files are upgrade-managed, so improvements are written as reviewable
proposals under `/opt/aaas/platform/reports/sop-improvements/` rather than
editing the native file in place. There is no mechanism for a proposal to take
effect before review; if an operator wants a change applied immediately, the
native SOP is patched directly with their explicit confirmation, and that
patch is the reviewed change.

## Platform Watchdog

`aaas-watchdog.sh` is a single, generic watchdog covering Agent Vault, every
tenant container, and the Hermes admin agent — there's no separate watchdog
per service. Install it once:

```bash
sudo /opt/aaas/platform/scripts/aaas-watchdog.sh --install
systemctl status aaas-watchdog.timer   # expect: active (waiting)
```

How it works:
- Runs every 5 minutes via a single systemd timer.
- Docker-based entities (Agent Vault, tenants) are discovered automatically
  via compose labels (`aaas.watchdog`, `aaas.watchdog.priority`,
  `aaas.watchdog.playbook`) — no separate registry to keep in sync. Docker's
  own `restart: unless-stopped` and container `HEALTHCHECK` already handle
  plain liveness; the watchdog only steps in when something is still
  unhealthy after Docker's own restart.
- Agent Vault is priority 0 and is checked first. If it's down and doesn't
  recover, the watchdog escalates Agent Vault only and skips the rest of
  that cycle — a vault outage breaks every tenant's LLM calls at once, so
  checking tenants too would just produce redundant, downstream-symptom
  reports. Hermes admin (priority 1, the one non-Docker entity, checked via
  HTTP probe) and tenants (priority 5 by default) are checked independently
  once Agent Vault is confirmed healthy.
- On a failure that survives two restart attempts, the watchdog writes an
  alert file (`/opt/aaas/platform/reports/{name}-ALERT.txt`) and invokes
  OpenCode against that entity's own incident playbook
  (`hermes-admin-failure.md`, `agent-vault-failure.md`, or
  `troubleshoot-tenant.md`) to diagnose, fix, and write a task report with
  `trigger: watchdog`.
- The watchdog's own files live under `/opt/aaas/platform/watchdog/` (not
  `reports/`, so they don't pollute report-indexing tooling), split by
  kind: `watchdog/logs/aaas-watchdog.log` (self-prunes entries older than
  30 days on every write, so it never grows unbounded) and
  `watchdog/state/aaas-watchdog.lock` (the run lock). Admin Hermes itself
  keeps no process log by platform policy — its stdout/stderr are
  discarded, not written to a file or the journal (see
  `admin-hermes/aaas-admin-hermes.service`).

## Monitoring Platform Health

`monitor-health` is the manual, deeper-dive counterpart to the watchdog above — run it for an operator-requested check, a post-incident review, or anything broader than restart-and-escalate (connectivity, network isolation, harness checks):

```bash
cd /opt/aaas/platform
opencode
# Tell the admin agent: "Run the monitor-health SOP"
```

The `monitor-health` SOP checks:
- Agent Vault health (container status, management API, proxy port reachability)
- Tenant status and connectivity (ping + Telegram API reachability)
- Docker and container readiness
- Infrastructure prerequisites (iptables-legacy enforcement, bridge networking)

Health check results are appended to task reports, so run `analyze-reports.sh` to spot trends and repeated failures across tenants.

For detailed incident diagnosis and recovery, see `/opt/aaas/platform/incidents/` for runbooks on known failure modes, including `agent-vault-failure.md`.

## What Gets Preserved on Upgrade

Running the installer against an existing `/opt/aaas/platform` installation
refreshes managed platform assets: `AGENTS.md`, `PLATFORM-REFERENCE.md`, `VERSION`, `CHANGELOG.md`, SOPs, skills,
templates, harness assets, eval assets, scripts, Hermes admin templates,
`platform/docker/Dockerfile`, and the knowledge vault scaffold (existing notes are never overwritten).

It preserves:

- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
- `/opt/aaas/agent-vault/.env` (Agent Vault master password — back this up externally; loss requires a full vault reset, see `platform/incidents/agent-vault-failure.md`)
- `/opt/aaas/agent-vault/data/` (Agent Vault database)
- `/opt/aaas/platform/reports/`
- `/opt/aaas/platform/vault/` (knowledge vault notes — only missing folders/files are scaffolded in; existing notes are left untouched)
- `/opt/aaas/platform/admin/` (the admin agent's deployed profile and secrets — diffed against current templates and refreshed only with operator confirmation, never overwritten automatically)
- The admin agent's Hermes install itself (`~/.local/bin/hermes`, `~/.hermes/hermes-agent/`) — outside `/opt/aaas/` entirely, untouched by platform upgrades; run `hermes update` separately if the `hermes-agent` package itself needs updating

If the installed `VERSION` is missing or older than the repository `VERSION`,
the installer upgrades the managed assets. Versioned upgrades save a backup
under `/opt/aaas/platform/backups/platform-assets-{timestamp}/` before
overwriting managed assets.

If the installed `VERSION` already matches the repository `VERSION`, the
installer asks whether to continue with a backup, continue without a backup, or
cancel. After upgrading, validate the installed setup:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --validate-only
```

Use `/opt/aaas/platform/sop/upgrade-platform.md` when asking the admin agent to perform
or review a platform setup upgrade. Rebuild the tenant Docker image separately
only when the upgrade notes or Dockerfile changes require it.

**Note on Agent Vault after upgrade:** If the upgrade includes a Dockerfile change
(CA certificate update), rebuild the tenant image and recreate tenant containers
to pick up the new CA. The CA is self-generated by Agent Vault and is fetched
during setup-agent-vault SOP step 3 — re-fetch it and rebuild if Agent Vault
was also redeployed with a fresh database. The Agent Vault container and its
database are unaffected by platform upgrades.

## Versioning

The platform setup version is manually tracked in `platform/VERSION`; release notes are tracked in [CHANGELOG.md](../CHANGELOG.md) and installed to `/opt/aaas/platform/CHANGELOG.md`.
This version covers the installed operating assets: `AGENTS.md`, `PLATFORM-REFERENCE.md`, SOPs,
skills, templates, Hermes admin templates, setup validation, and platform docs.

Bump `platform/VERSION` in the same change whenever platform behavior changes:

- Patch, for fixes that make the current workflow safer or more accurate, such as correcting a command, adding validation, or clarifying an SOP.
- Minor, for new operator-facing capabilities, such as a new SOP, new skill, report system, or new template behavior.
- Major, for breaking changes that require operators to relearn a workflow, migrate tenant files, or run a special upgrade path.

Do not bump `platform/VERSION` for tenant Docker image rebuilds only, tenant config
data changes only, typo-only edits, or tool version checks such as `docker --version`.
Those have separate meanings from the platform setup version.
