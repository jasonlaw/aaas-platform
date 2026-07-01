#!/usr/bin/env bash
# aaas-watchdog.sh
#
# Single generic watchdog covering Agent Vault, every tenant container, and
# admin Hermes. Replaces hermes-admin-watchdog.sh (admin-Hermes-only).
#
# Design:
#   - Docker already handles plain process liveness via `restart:
#     unless-stopped` + a container HEALTHCHECK. This script does NOT
#     duplicate that. It only steps in when a watched entity is still
#     unhealthy after Docker's own restart, and escalates to OpenCode with
#     the right incident playbook.
#   - Entities are discovered, not hardcoded:
#       * Docker entities: any container labelled `aaas.watchdog=true`,
#         carrying `aaas.watchdog.priority` (lower = checked first) and
#         `aaas.watchdog.playbook` (filename under platform/incidents/).
#       * admin Hermes is the one non-Docker entity (host process, run as
#         the platform operator's own user account — no dedicated service
#         account) and is registered below with the same priority/playbook
#         contract.
#   - Priority 0 is reserved for Agent Vault. If Agent Vault is down and
#     does not recover, the run escalates Agent Vault only and stops —
#     every tenant and admin Hermes failure in the same cycle is almost
#     certainly a downstream symptom (no LLM calls can succeed without the
#     vault proxy), so checking them too would just produce redundant
#     reports. Lower-priority entities are only checked once Agent Vault is
#     confirmed healthy.
#
# Install as a system-wide systemd timer:
#   sudo aaas-watchdog.sh --install

set -euo pipefail

PLATFORM_DIR="/opt/aaas/platform"
ADMIN_DIR="${PLATFORM_DIR}/admin"
REPORT_DIR="${PLATFORM_DIR}/reports"
# Everything this script itself owns (its own log, its own lock) lives under
# a dedicated watchdog/ folder, split into logs/ and state/ so the two kinds
# of file are never mixed: logs/ is human-readable, append-only history;
# state/ is machine-owned, mutated-in-place runtime state (currently just
# the lock). Nothing outside this script should need to know these paths.
WATCHDOG_DIR="${PLATFORM_DIR}/watchdog"
WATCHDOG_LOG_DIR="${WATCHDOG_DIR}/logs"
WATCHDOG_STATE_DIR="${WATCHDOG_DIR}/state"
WATCHDOG_LOG="${WATCHDOG_LOG_DIR}/aaas-watchdog.log"
LOCK_FILE="${WATCHDOG_STATE_DIR}/aaas-watchdog.lock"
ADMIN_DASHBOARD_HOST="127.0.0.1"
ADMIN_DASHBOARD_PORT="9119"
ADMIN_API_SERVER_PORT="8642"
ADMIN_HERMES_PRIORITY=1
ADMIN_HERMES_PLAYBOOK="hermes-admin-failure.md"
MAX_RESTART_ATTEMPTS=2
PROBE_TIMEOUT=15        # seconds to wait for a restarted entity to come back
# Admin Hermes's dashboard does a TypeScript/Vite build on its first start
# after install/upgrade, which can take up to ~60s before it responds — the
# shared 15s PROBE_TIMEOUT above is fine for Docker entities (whose
# healthcheck already absorbs their own startup time) but was too short for
# this one process, causing the watchdog to declare a restart "failed" and
# escalate to OpenCode while the dashboard was still mid-build.
ADMIN_HERMES_PROBE_TIMEOUT=90
OPENCODE_TIMEOUT=300
LOG_RETENTION_DAYS=30   # entries older than this are dropped on each prune pass

# --- Install mode ---
if [[ "${1:-}" == "--install" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Must run as root (sudo) to install the system watchdog unit." >&2
    exit 1
  fi

  # The unit itself still needs root once, to register with systemd. But
  # admin Hermes is a plain per-user install (no dedicated service account)
  # — the operator who ran platform setup owns /opt/aaas and
  # ~/.local/bin/hermes. Capture that operator once here via sudo's own
  # SUDO_USER (falls back to logname for a direct root login) and bake it
  # into the unit as User=; systemd resolves %h from User= at every run, so
  # this stays correct even if the unit file is ever copied to another box
  # — nothing here is a hardcoded path.
  OPERATOR_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  if [[ "$OPERATOR_USER" == "root" ]]; then
    echo "Warning: could not determine a non-root operator (SUDO_USER unset)." >&2
    echo "Installing the watchdog to run as root. Re-run via 'sudo ./aaas-watchdog.sh --install'" >&2
    echo "from the operator's own login shell to run admin Hermes as that user instead." >&2
  fi

  UNIT_DIR="/etc/systemd/system"

  cat > "$UNIT_DIR/aaas-watchdog.service" <<UNIT
[Unit]
Description=AaaS Platform Watchdog (Agent Vault, tenants, admin Hermes)
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
# User= is the operator account (captured at install time above), not
# root — it already owns /opt/aaas and is who admin Hermes was installed
# as (user mode, no dedicated service account). Restarting Docker
# containers still works under this user as long as they're in the docker
# group (setup-prerequisites.sh already adds them). %h expands to that
# user's \$HOME at every run via systemd itself, so ~/.local/bin/hermes
# resolves correctly with no baked-in path.
User=${OPERATOR_USER}
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${PLATFORM_DIR}/scripts/aaas-watchdog.sh
UNIT

  cat > "$UNIT_DIR/aaas-watchdog.timer" <<TIMER
[Unit]
Description=AaaS Platform Watchdog Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=aaas-watchdog.service

[Install]
WantedBy=timers.target
TIMER

  systemctl daemon-reload
  systemctl enable --now aaas-watchdog.timer
  echo "Watchdog installed. Check: systemctl status aaas-watchdog.timer"
  echo "Old per-service unit aaas-watchdog.service replaces hermes-admin-watchdog.service / .timer."
  echo "If those still exist, remove them: sudo systemctl disable --now hermes-admin-watchdog.timer; sudo rm -f $UNIT_DIR/hermes-admin-watchdog.*"
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
  mkdir -p "$WATCHDOG_LOG_DIR"
  prune_log "$WATCHDOG_LOG"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

write_alert() {
  local name="$1" detail="$2"
  mkdir -p "$REPORT_DIR"
  cat > "${REPORT_DIR}/${name}-ALERT.txt" <<EOF
${name} was unhealthy and did not recover after ${MAX_RESTART_ATTEMPTS} restart
attempts as of $(date '+%Y-%m-%d %H:%M:%S').
${detail}
OpenCode was invoked automatically; see reports/ for the troubleshoot report.
Remove this file once the issue is resolved and verified.
EOF
}

clear_alert() {
  rm -f "${REPORT_DIR}/${1}-ALERT.txt"
}

# Generic escalation: hand off to OpenCode with the entity's own incident
# playbook. Same shape for Agent Vault, any tenant, or admin Hermes — only
# the name and playbook differ.
escalate() {
  local name="$1" playbook="$2" extra="${3:-}"

  log "${name}: restart failed. Invoking OpenCode with ${playbook}."
  write_alert "$name" "$extra"

  if ! command -v opencode &>/dev/null; then
    log "${name}: opencode not in PATH. Manual intervention required."
    return 1
  fi

  timeout "${OPENCODE_TIMEOUT}" opencode \
    --non-interactive \
    --workdir "${PLATFORM_DIR}" \
    --message "${name} is down and automatic restart failed. \
Read /opt/aaas/platform/incidents/${playbook}, diagnose and fix the issue. \
Use /opt/aaas/platform/sop/write-report.md to write a troubleshoot report. \
Set the report's trigger field to watchdog (this session was started \
automatically by aaas-watchdog.sh, not by a human operator) and set \
operator_request to this exact message, verbatim, not a paraphrase. \
In the report, state clearly what was found, what was fixed, and if \
unresolved, exactly what the operator needs to do next." \
    >> "$WATCHDOG_LOG" 2>&1 || log "${name}: OpenCode exited with error or timed out."

  log "${name}: OpenCode invocation complete. See reports/ for the task report."
}

# --- Docker-entity check/restart ---

docker_is_healthy() {
  local name="$1"
  local status
  status="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo missing)"
  [[ "$status" == "running" ]] || return 1
  local health
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null)"
  [[ "$health" != "unhealthy" ]]
}

docker_restart() {
  docker restart "$1" >/dev/null 2>&1
}

wait_until_healthy() {
  local check_fn="$1" name="$2" timeout="${3:-$PROBE_TIMEOUT}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    "$check_fn" "$name" && return 0
    sleep 2
  done
  return 1
}

# --- Admin Hermes check/restart (the one non-Docker entity) ---

admin_hermes_is_healthy() {
  curl -sf --max-time 5 "http://${ADMIN_DASHBOARD_HOST}:${ADMIN_DASHBOARD_PORT}/" >/dev/null 2>&1 || return 1
  local key=""
  [[ -f "${ADMIN_DIR}/.env" ]] && key="$(grep -m1 '^API_SERVER_KEY=' "${ADMIN_DIR}/.env" | cut -d= -f2-)"
  # Key goes via a curl config file on stdin, never as a command-line arg,
  # so it never shows up in `ps`/`/proc/<pid>/cmdline` during this probe.
  printf 'header = "Authorization: Bearer %s"\n' "$key" \
    | curl -sf --max-time 5 -K - "http://127.0.0.1:${ADMIN_API_SERVER_PORT}/v1/models" >/dev/null 2>&1
}

admin_hermes_restart() {
  [[ -f "${ADMIN_DIR}/.env" ]] || { log "admin-hermes: ${ADMIN_DIR}/.env missing."; return 1; }
  # Prefer the systemd --user unit installed by setup-admin-hermes.md Step 7
  # — this keeps systemd as the single source of truth for the process
  # rather than racing a manually-backgrounded one against it. No sudo -u
  # wrapper needed: admin Hermes is a per-user install owned by whichever
  # account this watchdog itself runs as (User= in the systemd unit — see
  # --install above), same as every other command in this script.
  if systemctl --user list-unit-files aaas-admin-hermes.service &>/dev/null; then
    systemctl --user restart aaas-admin-hermes.service
    return
  fi
  log "admin-hermes: systemd --user unit not installed (re-run setup-admin-hermes.md Step 7). Falling back to nohup."
  # No log redirect here by design — admin Hermes does not get a process
  # log (see aaas-admin-hermes.service); discard stdout/stderr the same way
  # the systemd unit does instead of quietly reintroducing one here.
  bash -c "
    pkill -f 'hermes.*dashboard' 2>/dev/null || true
    sleep 2
    cd '${ADMIN_DIR}' && set -a && . ./.env && set +a
    nohup hermes dashboard --no-open >/dev/null 2>&1 &
  "
}

# --- Lock: flock self-releases on crash/kill, can't go stale like a touch'd
# file can. Lives under PLATFORM_DIR (operator-owned), not /var/run (root-owned
# and unwritable by the non-root operator this unit runs as). ---
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# --- Build the discovered Docker entity list, sorted by priority ---
# Each line: priority<TAB>name<TAB>playbook
docker_entities="$(
  docker ps -a --filter "label=aaas.watchdog=true" --format '{{.Names}}' 2>/dev/null | while read -r name; do
    [[ -z "$name" ]] && continue
    prio="$(docker inspect --format '{{ index .Config.Labels "aaas.watchdog.priority" }}' "$name" 2>/dev/null)"
    pb="$(docker inspect --format '{{ index .Config.Labels "aaas.watchdog.playbook" }}' "$name" 2>/dev/null)"
    [[ -z "$prio" ]] && prio=5      # default: below admin Hermes, tenant-tier
    [[ -z "$pb" ]] && pb="troubleshoot-tenant.md"
    printf '%s\t%s\t%s\n' "$prio" "$name" "$pb"
  done
)"

# Splice in admin Hermes as a virtual entity at its configured priority.
all_entities="$(printf '%s\n%s\t%s\t%s\n' "$docker_entities" \
  "$ADMIN_HERMES_PRIORITY" "admin-hermes" "$ADMIN_HERMES_PLAYBOOK" | grep -v '^\s*$' | sort -n -k1,1)"

# --- Priority 0 (Agent Vault) gate ---
vault_line="$(printf '%s\n' "$all_entities" | awk -F'\t' '$1 == 0' | head -1)"
if [[ -n "$vault_line" ]]; then
  vault_name="$(printf '%s' "$vault_line" | cut -f2)"
  vault_playbook="$(printf '%s' "$vault_line" | cut -f3)"
  if ! docker_is_healthy "$vault_name"; then
    log "${vault_name}: unhealthy. Attempting restart."
    recovered=1
    for attempt in $(seq 1 $MAX_RESTART_ATTEMPTS); do
      log "${vault_name}: restart attempt ${attempt}/${MAX_RESTART_ATTEMPTS}."
      docker_restart "$vault_name" || true
      if wait_until_healthy docker_is_healthy "$vault_name"; then
        log "${vault_name}: recovered on attempt ${attempt}."
        clear_alert "$vault_name"
        recovered=0
        break
      fi
      log "${vault_name}: attempt ${attempt} failed."
    done
    if [[ "$recovered" -ne 0 ]]; then
      escalate "$vault_name" "$vault_playbook" \
        "Agent Vault is the priority-0 dependency — tenant and admin Hermes checks were skipped this cycle since they would only be downstream symptoms."
      log "Skipping remaining checks this cycle: ${vault_name} is down."
      exit 0
    fi
  else
    clear_alert "$vault_name"
  fi
fi

# --- Check everything else (admin Hermes + tenants), independently ---
printf '%s\n' "$all_entities" | awk -F'\t' '$1 != 0' | while IFS=$'\t' read -r prio name playbook; do
  [[ -z "$name" ]] && continue

  if [[ "$name" == "admin-hermes" ]]; then
    check_fn=admin_hermes_is_healthy
    restart_fn=admin_hermes_restart
    probe_timeout=$ADMIN_HERMES_PROBE_TIMEOUT
  else
    check_fn=docker_is_healthy
    restart_fn=docker_restart
    probe_timeout=$PROBE_TIMEOUT
  fi

  if "$check_fn" "$name"; then
    clear_alert "$name"
    continue
  fi

  log "${name}: unhealthy. Attempting restart."
  recovered=1
  for attempt in $(seq 1 $MAX_RESTART_ATTEMPTS); do
    log "${name}: restart attempt ${attempt}/${MAX_RESTART_ATTEMPTS}."
    "$restart_fn" "$name" || true
    if wait_until_healthy "$check_fn" "$name" "$probe_timeout"; then
      log "${name}: recovered on attempt ${attempt}."
      clear_alert "$name"
      recovered=0
      break
    fi
    log "${name}: attempt ${attempt} failed."
  done
  if [[ "$recovered" -ne 0 ]]; then
    escalate "$name" "$playbook" ""
  fi
done

exit 0
