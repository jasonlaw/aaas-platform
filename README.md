# AaaS Platform

AaaS Platform is an OpenCode-managed Agent as a Service operations platform for running Hermes tenant agents in Docker. It installs a platform workspace under `/opt/aaas/platform`, keeps tenant data under `/opt/aaas/tenants`, and gives the OpenCode admin agent SOPs for building images, onboarding tenants, monitoring health, reviewing logs, upgrading tenants, and managing tenant lifecycle tasks.

## Install

Run the installer inside Ubuntu/Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```

Use the same command for fresh installs and platform setup upgrades. On a fresh
machine it runs the prerequisite bootstrap, installs the OpenCode platform setup,
and builds `hermes-tenant:latest`. On an existing installation it refreshes the
OpenCode platform setup and skips the image build by default.

To force an image rebuild during setup or upgrade:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash -s -- --build-image
```

## Use OpenCode

Always start OpenCode from the platform path:

```bash
cd /opt/aaas/platform
opencode
```

From there, OpenCode can use the platform SOPs to help you:

- Build and maintain the Hermes tenant Docker image
- Onboard new tenants
- Monitor tenant health and logs
- Suspend, reactivate, and offboard tenants
- Upgrade tenants to a newer image
- Update tenant configuration safely

Ask OpenCode what skills are available, then tell it the tenant operation you want to perform.

## Task Reports

After every SOP task, OpenCode must write a report before declaring completion.
Full reports live under `/opt/aaas/platform/reports/{sop-name}/`, and compact
AI-readable summaries are appended to `/opt/aaas/platform/reports/INDEX.jsonl`.

Use the Markdown report for human audit details. Use `INDEX.jsonl` for fast AI
review, trend spotting, and future platform improvement work without rereading
every historical report. Reports must never contain secrets; redact API keys,
bot tokens, access tokens, private URLs, and customer private data.

## Upgrade Platform Setup

To upgrade an existing `/opt/aaas/platform` installation to the latest OpenCode
platform setup, rerun the same setup link:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```

This refreshes managed OpenCode assets: `AGENTS.md`, `VERSION`, SOPs, skills,
templates, and `platform/docker/Dockerfile`.

It preserves:

- `/opt/aaas/tenants/`
- `/opt/aaas/platform/tenants.yaml`
- `/opt/aaas/platform/docker/docker-compose.yaml`
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

Use `/opt/aaas/platform/sop/upgrade-platform.md` when asking OpenCode to perform
or review a platform setup upgrade. Rebuild the tenant Docker image separately
only when the upgrade notes or Dockerfile changes require it.

## Versioning

The OpenCode platform setup version is manually tracked in `platform/VERSION`.
This version covers the installed OpenCode operating assets: `AGENTS.md`, SOPs,
skills, templates, setup validation, and platform docs.

Bump `platform/VERSION` in the same change whenever platform behavior changes:

- Patch, for fixes that make the current workflow safer or more accurate, such as correcting a command, adding validation, or clarifying an SOP.
- Minor, for new operator-facing capabilities, such as a new SOP, new skill, report system, or new template behavior.
- Major, for breaking changes that require operators to relearn a workflow, migrate tenant files, or run a special upgrade path.

Do not bump `platform/VERSION` for tenant Docker image rebuilds only, tenant config
data changes only, typo-only edits, or tool version checks such as `docker --version`.
Those have separate meanings from the OpenCode platform setup version.
