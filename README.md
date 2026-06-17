# AaaS Platform

AaaS Platform is an OpenCode-managed Agent as a Service operations platform for running Hermes tenant agents in Docker. It installs a platform workspace under `/opt/aaas/platform`, keeps tenant data under `/opt/aaas/tenants`, and gives the OpenCode admin agent SOPs for building images, onboarding tenants, monitoring health, reviewing logs, upgrading tenants, and managing tenant lifecycle tasks.

## Install

Run the full installer inside Ubuntu/Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/jasonlaw/aaas-platform/main/scripts/setup.sh | bash
```

The installer combines the prerequisite bootstrap and OpenCode platform setup, then always builds the `hermes-tenant:latest` Docker image.

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
