#!/usr/bin/env bash
# hermes-admin-watchdog.sh
#
# Lightweight watchdog for the Hermes admin agent.
# Runs every 5 minutes via systemd user timer.
#
# Behaviour:
#   1. If Hermes admin is up and responsive — exit silently.
#   2. If down — attempt a direct restart (up to 2 times).
#   3. If restart succeeds — exit silently.
#   4. If restart fails — invoke OpenCode to diagnose, fix, and write a
#      troubleshoot-platform report. OpenCode is responsible for the report
#      and for deciding when to stop and state clearly in the report what
#      the operator needs to do next.
#
# Install as a systemd user timer:
#   hermes-admin-watchdog.sh --install

set -euo pipefail

PLATFORM_DIR="/opt/aaas/platform"
ADMIN_DIR="${PLATFORM_DIR}/admin"
LOG_DIR="${PLATFORM_DIR}/logs"
WATCHDOG_LOG="${LOG_DIR}/hermes-admin-watchdog.log"
HERMES_PROC_LOG="${LOG_DIR}/hermes-admin.log"
LOCK_FILE="/tmp/hermes-admin-watchdog.lock"
DASHBOARD_HOST="127.0.0.1"
DASHBOARD_PORT="9119"
API_SERVER_PORT="8642"
MAX_RESTART_ATTEMPTS=2
PROBE_TIMEOUT=15    # seconds to wait for dashboard after restart
OPENCODE_TIMEOUT=300
LOG_RETENTION_DAYS=30   # entries older than this are dropped on each prune pass

# --- Install mode ---
if [[ "${1:-}" == "--install" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Must run as root (sudo) to install the system watchdog unit." >&2
    exit 1
  fi

  UNIT_DIR="/etc/systemd/system"

  cat > "$UNIT_DIR/hermes-admin-watchdog.service" <<UNIT
[Unit]
Description=Hermes Admin Agent Watchdog
After=network-online.target

[Service]
Type=oneshot
User=aaas
Environment=PATH=/opt/aaas/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${PLATFORM_DIR}/scripts/hermes-admin-watchdog.sh
UNIT

  cat > "$UNIT_DIR/hermes-admin-watchdog.timer" <<TIMER
[Unit]
Description=Hermes Admin Agent Watchdog Timer
Requires=hermes-admin-watchdog.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=hermes-admin-watchdog.service

[Install]
WantedBy=timers.target
TIMER

  systemctl daemon-reload
  systemctl enable --now hermes-admin-watchdog.timer
  echo "Watchdog installed. Check: systemctl status hermes-admin-watchdog.timer"
  exit 0
fi

# --- Helpers ---

# Drop log lines older than LOG_RETENTION_DAYS. Cheap single-pass awk, only
# invoked when we're about to write (state-change events), never on the
# silent healthy-check path — so this never runs on the vast majority of
# 5-minute ticks.
prune_log() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local cutoff
  cutoff="$(date -d "-${LOG_RETENTION_DAYS} days" '+%Y-%m-%d' 2>/dev/null \
    || date -v-"${LOG_RETENTION_DAYS}"d '+%Y-%m-%d' 2>/dev/null)" || return 0
  awk -v cutoff="$cutoff" '
    /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
      ts = substr($0, 2, 10)
      if (ts < cutoff) next
    }
    { print }  # keep dated-and-current lines, plus malformed/continuation
               # lines rather than risk dropping data
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

log() {
  mkdir -p "$LOG_DIR"
  prune_log "$WATCHDOG_LOG"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

is_responsive() {
  curl -sf --max-time 5 "http://${DASHBOARD_HOST}:${DASHBOARD_PORT}/" >/dev/null 2>&1 || return 1
  # ponytail: reuses ADMIN_DIR/.env already loaded by start_hermes's subshell;
  # here we just need API_SERVER_KEY in our own env, so source it directly.
  local key=""
  [[ -f "${ADMIN_DIR}/.env" ]] && key="$(grep -m1 '^API_SERVER_KEY=' "${ADMIN_DIR}/.env" | cut -d= -f2-)"
  curl -sf --max-time 5 -H "Authorization: Bearer ${key}" \
    "http://127.0.0.1:${API_SERVER_PORT}/v1/models" >/dev/null 2>&1
}

start_hermes() {
  [[ -f "${ADMIN_DIR}/.env" ]] || { log "ERROR: ${ADMIN_DIR}/.env missing."; return 1; }
  pkill -f "hermes.*dashboard" 2>/dev/null || true
  sleep 2
  mkdir -p "$LOG_DIR"
  (cd "${ADMIN_DIR}" && set -a && . ./.env && set +a &&
    nohup hermes dashboard --no-open \
      >> "${HERMES_PROC_LOG}" 2>&1 &)
}

wait_for_responsive() {
  local deadline=$(( $(date +%s) + PROBE_TIMEOUT ))
  while (( $(date +%s) < deadline )); do
    is_responsive && return 0
    sleep 2
  done
  return 1
}

# --- Lock ---
[[ -e "$LOCK_FILE" ]] && exit 0
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

# --- Check ---
is_responsive && exit 0

log "Hermes admin is down. Attempting restart."

for attempt in $(seq 1 $MAX_RESTART_ATTEMPTS); do
  log "Restart attempt ${attempt}/${MAX_RESTART_ATTEMPTS}."
  start_hermes && wait_for_responsive && { log "Recovered on attempt ${attempt}."; exit 0; }
  log "Attempt ${attempt} failed."
done

# Restart failed — hand off to OpenCode to diagnose and write the report.
log "Restart failed. Invoking OpenCode."

if ! command -v opencode &>/dev/null; then
  log "opencode not in PATH. Manual intervention required."
  exit 1
fi

timeout "${OPENCODE_TIMEOUT}" opencode \
  --non-interactive \
  --workdir "${PLATFORM_DIR}" \
  --message "Hermes admin is down and automatic restart failed. \
Read /opt/aaas/platform/incidents/hermes-admin-failure.md, diagnose and fix the issue. \
Use /opt/aaas/platform/sop/write-report.md to write a troubleshoot-platform report. \
Set the report's trigger field to watchdog (this session was started \
automatically by hermes-admin-watchdog.sh, not by a human operator) and \
set operator_request to this exact message, verbatim, not a paraphrase. \
In the report, state clearly what was found, what was fixed, and if unresolved, \
exactly what the operator needs to do next." \
  >> "$WATCHDOG_LOG" 2>&1 || log "OpenCode exited with error or timed out."

log "OpenCode invocation complete. Watchdog log in logs/; see reports/ for the task report."
