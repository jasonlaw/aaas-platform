#!/usr/bin/env bash
# Replaces the bare `gateway run` command in docker-compose.yaml. Runs
# reconcile-plugins.sh (best-effort, never blocking) before handing off to
# the real gateway process via `exec`, so `docker inspect`/healthcheck/
# `pgrep -f 'gateway run'` all still see the same process they always did.
#
# --- gateway resolution (hardened 2026-07-05) -------------------------------
# The base image (nousresearch/hermes-agent) sets, at the Docker layer:
#   ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"
# which applies to every process in the container regardless of this
# script's own `command:` override, so `gateway` should normally resolve
# without any extra venv activation. A prior incident's remediation notes
# claimed `exec gateway run` needed `. venv/bin/activate` first, but that
# claim was never reconciled against this base-image PATH behaviour and no
# corresponding fix was ever committed here — this may have been masking a
# different root cause (stale image layer, unrebuilt container, etc.)
# rather than a real gap in this script.
#
# Rather than re-adding an unverified `source venv/bin/activate` unconditionally,
# this checks whether `gateway` actually resolves first and only falls back
# if it doesn't — so a real PATH problem still gets handled, but we're not
# silently masking it either: the fallback path logs clearly, so if it's
# ever hit on a real container that's a concrete signal the base-image PATH
# assumption above doesn't hold for that image and needs escalating upstream,
# rather than a silent workaround nobody notices relying on.
set -uo pipefail

if [ -x /opt/data/scripts/reconcile-plugins.sh ]; then
  /opt/data/scripts/reconcile-plugins.sh || echo "[tenant-entrypoint] reconcile-plugins.sh failed, continuing startup"
fi

if ! command -v gateway >/dev/null 2>&1; then
  echo "[tenant-entrypoint] WARNING: 'gateway' not found on PATH ($PATH)." >&2
  echo "[tenant-entrypoint] This is unexpected — the base image should put it there. Falling back to venv activation." >&2
  if [ -f /opt/hermes/.venv/bin/activate ]; then
    # shellcheck disable=SC1091
    . /opt/hermes/.venv/bin/activate
    echo "[tenant-entrypoint] Activated /opt/hermes/.venv — please report this fallback path being hit, it indicates a base-image PATH regression." >&2
  else
    echo "[tenant-entrypoint] /opt/hermes/.venv/bin/activate not found either; trying 'hermes gateway run' directly." >&2
    exec hermes gateway run
  fi
fi

exec gateway run
