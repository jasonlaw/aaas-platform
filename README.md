# AaaS Platform

AaaS Platform is an Agent as a Service operations platform for running Hermes tenant agents in Docker. It installs a platform workspace under `/opt/aaas/platform`, keeps tenant data under `/opt/aaas/tenants`, and gives OpenCode SOPs for building images, onboarding tenants, monitoring health, reviewing logs, upgrading tenants, and managing tenant lifecycle tasks.

Credentials (LLM API keys and other secrets) are never stored in tenant containers or `.env` files. They are managed exclusively by a local [Agent Vault](https://github.com/Infisical/agent-vault) instance that acts as a transparent MITM proxy, injecting credentials at the network layer so agents never hold live keys.

## Install

Run the installer inside Ubuntu/Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```

Use the same command for fresh installs and platform setup upgrades. On a fresh
machine it runs the prerequisite bootstrap, installs the platform setup,
and builds `hermes-tenant:latest`. On an existing installation it refreshes the
platform setup and skips the image build by default.

To force an image rebuild during setup or upgrade:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --build-image
```

## First-Time Setup: Agent Vault

`setup-platform.sh` automatically handles the infrastructure side of Agent Vault:
creates `/opt/aaas/agent-vault/` (peer to `platform/`, not inside it), writes its
standalone `docker-compose.yaml`, creates the `.env` stub for the master password,
pulls the image, and starts the container if the password is already set.

After the installer finishes, complete setup via OpenCode:

```bash
cd /opt/aaas/platform
opencode
# Tell the admin agent: "Complete the Agent Vault setup"
```

This covers the steps that need a running container: registering the owner account,
fetching the MITM CA certificate, patching the tenant Dockerfile to trust it, and
rebuilding the tenant image. It is a one-time operation per server.

If Agent Vault was not started by the installer (master password not set yet):
```bash
# 1. Set the password
nano /opt/aaas/agent-vault/.env
# Fill in: AGENT_VAULT_MASTER_PASSWORD=<your-password>

# 2. Start the container
docker compose -f /opt/aaas/agent-vault/docker-compose.yaml up -d agent-vault

# 3. Then complete setup via OpenCode as above
```

See `/opt/aaas/platform/sop/setup-agent-vault.md` for the full post-install SOP.

## Use OpenCode

Always start OpenCode from the platform path:

```bash
cd /opt/aaas/platform
opencode
```

From there, OpenCode can use the platform SOPs to help you:

- Set up Agent Vault credential broker (one-time, before first tenant)
- Build and maintain the Hermes tenant Docker image
- Onboard new tenants (includes automatic vault provisioning)
- Monitor tenant health and logs (includes Agent Vault health check)
- Suspend, reactivate, and offboard tenants (includes vault cleanup)
- Upgrade tenants to a newer image
- Update tenant configuration safely
- Rotate LLM API keys without container restarts
- Improve SOPs through local overrides or proposals without editing upgrade-managed native SOPs

Ask the admin agent what skills are available, then tell it the tenant operation you want to perform.

Hermes admin support is optional. To set up Hermes as an admin dashboard later,
start OpenCode and ask it to use the `setup-admin-hermes` skill. The base setup
ships managed Hermes admin templates under `/opt/aaas/platform/admin-hermes`,
but it does not activate or configure Hermes automatically.

## Credential Security Model

Tenant containers never hold real LLM API keys. The flow is:

1. **Agent Vault** stores the real key encrypted at rest (AES-256-GCM).
2. During onboarding, the admin agent runs `provision-tenant-vault` which creates a scoped vault, stores the key, and mints a proxy token for the tenant.
3. The tenant `.env` receives `HTTP_PROXY`/`HTTPS_PROXY` pointing at Agent Vault's MITM proxy port, plus the scoped proxy token. The LLM key env var is set to the placeholder `routed-via-agent-vault`.
4. When the tenant container makes an outbound LLM API call, Agent Vault intercepts the TLS connection, injects the real key into the `Authorization` header, and forwards the request. The tenant container sees only the proxy token.

To rotate a tenant's LLM API key at any time — with no container restart:
```bash
agent-vault vault credential update {tenant-id}-vault --host {provider-hostname} --secret {new-key}
```

## Task Reports

After every SOP task or operational troubleshooting work, the admin agent must write a report before declaring completion.
Use the [write-report](platform/sop/write-report.md) SOP for detailed guidance.

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

## Tenant Harness

The platform installs tenant harness assets under `/opt/aaas/platform/harness`,
required SOP checklists under `/opt/aaas/platform/checklists`, and eval assets
under `/opt/aaas/platform/evals`.

Every tenant should have `/opt/aaas/tenants/{tenant-id}/harness.yaml` and
`/opt/aaas/tenants/{tenant-id}/ACCEPTANCE.md`. The admin agent uses these files,
plus `/opt/aaas/platform/harness/check-tenant.sh {tenant-id}`, to prove that the
tenant gets a brand-aware, private, owner-safe assistant rather than only a
running Docker container.

Tenant behavioral validation has two eval layers:

- Fixed safety eval: `/opt/aaas/platform/evals/tenant-agent/_fixed-safety-v1.yaml`
- Generated tenant eval: `/opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml`

Run evals once the tenant container is running:

```bash
/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/evals/tenant-agent/_fixed-safety-v1.yaml
/opt/aaas/platform/scripts/eval-runner.sh {tenant-id} /opt/aaas/platform/evals/tenant-agent/generated/{tenant-id}-v1.yaml
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
SOP files are upgrade-managed, so local active overrides belong under
`/opt/aaas/platform/local/sop/`, while reviewable improvement proposals belong
under `/opt/aaas/platform/reports/sop-improvements/`.

## Upgrade Platform Setup

To upgrade an existing `/opt/aaas/platform` installation to the latest
platform setup, rerun the same setup link:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```

This refreshes managed platform assets: `AGENTS.md`, `VERSION`, `CHANGELOG.md`, SOPs, skills,
templates, harness assets, eval assets, scripts, Hermes admin templates, and
`platform/docker/Dockerfile`.

It preserves:

- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
- `/opt/aaas/platform/docker/.env` (Agent Vault master password)
- `/opt/aaas/agent-vault/data/` (Agent Vault database)
- `/opt/aaas/platform/reports/`

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
to pick up the new CA. The Agent Vault container and its database are unaffected
by platform upgrades.

## Monitoring Platform Health

Monitor tenant and platform health by asking the admin agent to use the `monitor-health` SOP:

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

## Versioning

The platform setup version is manually tracked in `platform/VERSION`; release notes are tracked in [CHANGELOG.md](CHANGELOG.md) and installed to `/opt/aaas/platform/CHANGELOG.md`.
This version covers the installed operating assets: `AGENTS.md`, SOPs,
skills, templates, Hermes admin templates, setup validation, and platform docs.

Bump `platform/VERSION` in the same change whenever platform behavior changes:

- Patch, for fixes that make the current workflow safer or more accurate, such as correcting a command, adding validation, or clarifying an SOP.
- Minor, for new operator-facing capabilities, such as a new SOP, new skill, report system, or new template behavior.
- Major, for breaking changes that require operators to relearn a workflow, migrate tenant files, or run a special upgrade path.

Do not bump `platform/VERSION` for tenant Docker image rebuilds only, tenant config
data changes only, typo-only edits, or tool version checks such as `docker --version`.
Those have separate meanings from the platform setup version.