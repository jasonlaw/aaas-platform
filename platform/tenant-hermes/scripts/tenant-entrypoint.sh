#!/usr/bin/env bash
# Replaces the bare `gateway run` command in docker-compose.yaml. Runs
# reconcile-plugins.sh (best-effort, never blocking) before handing off to
# the real gateway process via `exec`, so `docker inspect`/healthcheck/
# `pgrep -f 'gateway run'` all still see the same process they always did.
set -uo pipefail

if [ -x /opt/data/scripts/reconcile-plugins.sh ]; then
  /opt/data/scripts/reconcile-plugins.sh || echo "[tenant-entrypoint] reconcile-plugins.sh failed, continuing startup"
fi

exec gateway run
