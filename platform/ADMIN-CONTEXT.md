# AaaS Admin Context

This document is shared admin context for the AaaS (Agent as a Service) platform.

It gives admin agents the shared platform map, conventions, operating principles, available assets, and platform-wide invariants. SOP-specific procedures
belong in the SOP files listed below. Agent-specific identity,
responsibilities, and behavioral instructions are defined in their own
instruction files.

## Operating Principles

These principles apply to all platform operations unless a specific SOP
or platform rule states otherwise.

- Follow documented procedures before improvising.
- Read the relevant SOP before performing an operational task.
- Search existing SOPs, skills, scripts, incident playbooks, and
  previous task reports before implementing a new solution.
- Prefer existing automation over manual changes.
- Run the platform preflight check whenever Docker, networking,
  certificates, host configuration, or platform state may affect the
  task.
- Validate the outcome before declaring work complete.
- Record operational work and significant findings using
  `write-report.md`.
- Confirm before destructive or irreversible actions.

## Platform Layout

### Core Files

| Purpose | Location |
|----------|----------|
| Platform version | `/opt/aaas/platform/VERSION` |
| Tenant registry | `/opt/aaas/platform/tenants.yaml` |
| Docker Compose | `/opt/aaas/platform/docker/docker-compose.yaml` |
| Platform policy | `/opt/aaas/platform/policy/platform-policy.yaml` |

### Directories

| Purpose | Location |
|----------|----------|
| Tenant data | `/opt/aaas/tenants/` |
| SOPs | `/opt/aaas/platform/sop/` |
| Skills | `/opt/aaas/platform/skills/` |
| Utility scripts | `/opt/aaas/platform/scripts/` |
| Incident playbooks | `/opt/aaas/platform/incidents/` |
| Reports | `/opt/aaas/platform/reports/` |
| Harness | `/opt/aaas/platform/harness/` |
| Checklists | `/opt/aaas/platform/checklists/` |
| Tenant templates | `/opt/aaas/platform/tenant-hermes/` |
| Admin templates | `/opt/aaas/platform/admin-hermes/` |
| Tenant evals | `/opt/aaas/platform/tenant-hermes/evals/` |
| Admin evals | `/opt/aaas/platform/evals/` |
| Backups | `/opt/aaas/platform/backups/` |

### Watchdog

| Purpose | Location |
|----------|----------|
| Logs | `/opt/aaas/platform/watchdog/logs/` |
| Runtime state | `/opt/aaas/platform/watchdog/state/` |

## Docker Conventions

### Tenant Containers

- One Docker Compose service per tenant.
- Service name: `hermes_{tenant-id}`
- Container name: `hermes_{tenant-id}`
- Image: `hermes-tenant:latest`
- Startup command:
  `/opt/data/scripts/tenant-entrypoint.sh`

### Docker Compose

- Compose file:
  `/opt/aaas/platform/docker/docker-compose.yaml`
- Services are defined under the root `services:` mapping.
- Start or recreate only the required service:
  `docker compose up -d {service-name}`
- Never operate on every service unless explicitly intended.

### Volume Mounts

| Host | Container |
|------|-----------|
| `/opt/aaas/tenants/{tenant-id}` | `/opt/data` |
| `/opt/aaas/tenants/{tenant-id}/files` | `/home/hermes/files` |
| `/opt/aaas/tenants/{tenant-id}/vault` | `/home/hermes/vault` |

### Container Startup

Every tenant container starts through
`/opt/data/scripts/tenant-entrypoint.sh`.

Startup sequence:

1. Run `reconcile-plugins.sh`.
2. Start the Hermes gateway.

## Tenant Data

Each tenant stores persistent data under:

`/opt/aaas/tenants/{tenant-id}/`

### Configuration

| Purpose | File |
|----------|------|
| Environment | `.env` |
| Configuration | `config.yaml` |
| Tenant policy | `tenant-policy.yaml` |
| Harness | `harness.yaml` |
| Acceptance | `ACCEPTANCE.md` |

### Platform Metadata

| Purpose | Location |
|----------|----------|
| Tenant registry | `/opt/aaas/platform/tenants.yaml` |
| Docker services | `/opt/aaas/platform/docker/docker-compose.yaml` |

### Knowledge Vault

Tenant knowledge is stored under:

`/opt/aaas/tenants/{tenant-id}/vault/`

The knowledge vault is:

- durable
- maintained by the tenant
- owner-browsable
- independent of Mnemosyne
- never synchronized into Mnemosyne

## Platform Assets

### SOPs

| Operation | SOP |
|-----------|-----|
| Build image | `build-image.md` |
| Upgrade platform | `upgrade-platform.md` |
| Upgrade tenants | `upgrade-tenants.md` |
| Onboard tenant | `onboard-tenant.md` |
| Suspend tenant | `suspend-tenant.md` |
| Reactivate tenant | `reactivate-tenant.md` |
| Offboard tenant | `offboard-tenant.md` |
| Update tenant | `update-tenant.md` |
| Health check | `monitor-health.md` |
| Log review | `monitor-logs.md` |
| Troubleshooting | `troubleshoot-tenant.md` |
| Improve SOP | `improve-sop.md` |
| Write report | `write-report.md` |
| Setup Agent Vault | `setup-agent-vault.md` |
| Provision tenant vault | `provision-tenant-vault.md` |
| Deprovision tenant vault | `deprovision-tenant-vault.md` |

### Skills

| Skill | Purpose |
|---------|---------|
| `grill-me.md` | Interactive review |
| `setup-admin-hermes.md` | Hermes admin setup |
| `manage-agent-vault.md` | Runtime Agent Vault management |
| `handle-tenant-request.md` | Tenant request handling |
| `handle-watchdog-alert.md` | Watchdog alert handling |

## Platform Invariants

These are always-loaded platform rules. Step-by-step procedures,
completion gates, report formats, and recovery paths belong in the
relevant SOP.

### Operator Confirmation

Confirm before:

- deleting tenant data
- recreating containers
- writing or rotating credentials
- destructive operations
- actions affecting multiple tenants
- irreversible platform changes

### Security

- Never expose one tenant's data to another.
- Never infer permission across tenants.
- Never persist credentials outside their approved storage.
- Store LLM API keys exclusively in Agent Vault.
- Store non-LLM credentials only in `.env`.
- Never store real LLM API keys in `.env`.
- Never reveal credential values after writing or rotating them.

### Docker

- Operate only on the intended tenant service.
- Never run `docker compose up -d` without specifying a service.
- Never use `docker compose down` to resolve a single-tenant issue.
- Never use `docker compose restart` for configuration, secret,
  network, or policy changes.
- Recreate containers only when required by image, configuration,
  secret, network, or policy changes.
- Confirm before recreating a tenant container.

### Networking

- Maintain the required Docker networking configuration.
- Verify host networking prerequisites before troubleshooting Docker
  connectivity.
- Apply documented nftables fixes through the provided platform
  scripts rather than manual firewall changes.
- Use tenant-isolated Docker networks.

### Policy

- Platform policy is defined by
  `/opt/aaas/platform/policy/platform-policy.yaml`.
- Tenant policy may only further restrict platform policy.
- Never hand-edit generated policy artifacts.
- Regenerate policy-derived assets after changing platform policy.

### Runtime

- Every tenant owns an isolated knowledge vault.
- Runtime plugins must be installed using the supported installer.
- Runtime plugins are restored automatically during container startup.
- Use Mnemosyne only for conversational memory.
- Keep knowledge vaults separate from Mnemosyne.