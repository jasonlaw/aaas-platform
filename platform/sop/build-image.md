# SOP: Build Hermes Docker Image

## Purpose
Build or rebuild the custom Hermes tenant image.
Run when: first setup, Mnemosyne update, fastembed update, or Dockerfile change.

## Steps
1. Confirm with operator: "This will rebuild hermes-tenant Docker image. Proceed? (y/n)"
2. Pull latest official base image: `docker pull nousresearch/hermes-agent:latest`
3. Build custom image:
   `cd /opt/aaas/platform/docker`
   `docker build -t hermes-tenant:latest .`
4. Tag with date: `docker tag hermes-tenant:latest hermes-tenant:$(date +%Y%m%d)`
5. Verify: `docker images | grep hermes-tenant`
6. Report image size and tags created.

## Notes
- Existing tenant containers are not affected until upgrade-tenants.md is run.
- fastembed download is large on first build.
