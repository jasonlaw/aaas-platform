# SOP: Build Hermes Docker Image

## Purpose
Build or rebuild the custom Hermes tenant image.
Run when: first setup, Mnemosyne update, fastembed update, or Dockerfile change.

## Steps
1. Confirm with operator: "This will rebuild hermes-tenant Docker image. Proceed? (y/n)"
2. Run `/opt/aaas/platform/scripts/preflight-check.sh`.
3. Verify the Agent Vault MITM CA certificate is present in the Docker build context:
   ```bash
   ls /opt/aaas/platform/docker/agent-vault-ca.pem
   ```
   If missing, Agent Vault has not been set up yet (or was redeployed with a fresh
   database). Fetch it before continuing:
   ```bash
   curl -o /opt/aaas/platform/docker/agent-vault-ca.pem http://localhost:14321/v1/mitm/ca.pem
   ```
   See setup-agent-vault.md step 3 for full details.
4. Pull latest official base image: `docker pull nousresearch/hermes-agent:latest`
5. Build custom image:
   `cd /opt/aaas/platform/docker`
   `docker build -t hermes-tenant:latest .`
6. Tag with date: `docker tag hermes-tenant:latest hermes-tenant:$(date +%Y%m%d)`
7. Verify: `docker images | grep hermes-tenant`
8. Report image size and tags created.

## Notes
- Existing tenant containers are not affected until upgrade-tenants.md is run.
- fastembed download is large on first build.
