#!/usr/bin/env bash
set -euo pipefail

# launchd watchdog for copilot-relay. Two tiers, because the cheap check and
# the meaningful check have very different costs:
#
#   1. Liveness — every run (StartInterval, 60s). GET /healthz. Free and fast,
#      but /healthz is a static handler in copilot-relay that never contacts
#      GitHub Copilot, so 200 proves only that a socket is listening. A relay
#      whose Copilot token expired an hour ago still answers 200.
#
#   2. Deep — time-gated (default every 900s). `copilot-relay status --deep`
#      sends a real request through Copilot, exercising token refresh, the
#      upstream round trip, and translation. This is the only check that
#      catches a relay that is listening but cannot reach Copilot. It spends
#      a few tokens per run, hence the long interval.
#
# `status --deep` exit codes (requires copilot-relay >= 0.2.6, which
# install.sh keeps current):
#   0  running and reachable
#   1  not running
#   2  running but not usable (health probe or upstream round trip failed)
#
# 1 and 2 are logged distinctly: a restart fixes 1, but 2 is usually expired
# auth, where the real fix is `copilot-relay auth` and a restart just loops.
#
# Tuning (all optional env vars):
#   COPILOT_RELAY_DEEP_INTERVAL   seconds between deep checks; 0 disables
#   COPILOT_RELAY_DEEP_MAX_TIME   seconds before a hung deep check is killed

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

label="${COPILOT_RELAY_LABEL:-com.d0n9x1n.copilot-relay}"
url="${COPILOT_RELAY_HEALTH_URL:-http://127.0.0.1:4142/healthz}"
plist="${COPILOT_RELAY_PLIST:-${HOME}/Library/LaunchAgents/${label}.plist}"
log_file="${COPILOT_RELAY_HEALTH_LOG:-${HOME}/Library/Logs/copilot-relay-healthcheck.log}"
log_max_lines="${COPILOT_RELAY_HEALTH_LOG_MAX_LINES:-500}"
connect_timeout="${COPILOT_RELAY_HEALTH_CONNECT_TIMEOUT:-1}"
max_time="${COPILOT_RELAY_HEALTH_MAX_TIME:-3}"
deep_interval="${COPILOT_RELAY_DEEP_INTERVAL:-900}"
deep_max_time="${COPILOT_RELAY_DEEP_MAX_TIME:-45}"
deep_stamp="${COPILOT_RELAY_DEEP_STAMP:-${HOME}/Library/Caches/copilot-relay-healthcheck.deep}"
uid="$(id -u)"

mkdir -p "$(dirname "$log_file")"
mkdir -p "$(dirname "$deep_stamp")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  printf '[%s] %s\n' "$(ts)" "$*" >>"$log_file"
}

cap_log() {
  [ -f "$log_file" ] || return 0
  tail -n "$log_max_lines" "$log_file" >"${log_file}.tmp" 2>/dev/null \
    && mv "${log_file}.tmp" "$log_file" \
    || rm -f "${log_file}.tmp" 2>/dev/null || true
}

# Darwin stat first, GNU stat as fallback (repo convention).
file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

# macOS has no coreutils `timeout`, and a hung deep check would block this
# agent indefinitely — launchd will not start a second instance while the
# first is still running, so one hang silently ends the watchdog. Bound it.
# Returns 124 when the command had to be killed, mirroring coreutils.
run_with_timeout() {
  local secs="$1"
  shift
  local cmd_pid killer_pid rc

  "$@" &
  cmd_pid=$!

  (
    sleep "$secs"
    kill -TERM "$cmd_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$cmd_pid" 2>/dev/null || true
  ) >/dev/null 2>&1 &
  killer_pid=$!

  rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?

  kill -KILL "$killer_pid" 2>/dev/null || true
  wait "$killer_pid" 2>/dev/null || true

  # 143 SIGTERM / 137 SIGKILL: the killer fired.
  if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then
    return 124
  fi
  return "$rc"
}

health_code() {
  curl -sS -o /dev/null \
    --connect-timeout "$connect_timeout" \
    --max-time "$max_time" \
    -w '%{http_code}' \
    "$url" 2>/dev/null || true
}

wait_for_health() {
  local attempt code
  attempt=1
  while [ "$attempt" -le 20 ]; do
    code="$(health_code)"
    if [ "$code" = "200" ]; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  return 1
}

kickstart_relay() {
  if launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/${uid}/${label}" >/dev/null 2>&1 \
      || log "failed to kickstart loaded ${label}"
  elif [ -f "$plist" ]; then
    launchctl bootstrap "gui/${uid}" "$plist" >/dev/null 2>&1 \
      || log "failed to bootstrap ${label} from $plist"
    launchctl kickstart -k "gui/${uid}/${label}" >/dev/null 2>&1 \
      || log "failed to kickstart bootstrapped ${label}"
  else
    log "cannot start ${label}: plist missing at $plist"
    return 1
  fi
  return 0
}

deep_due() {
  local now last
  [ "$deep_interval" -gt 0 ] || return 1
  [ -f "$deep_stamp" ] || return 0
  now="$(date +%s)"
  last="$(file_mtime "$deep_stamp")"
  [ $((now - last)) -ge "$deep_interval" ]
}

deep_status() {
  local rc=0
  run_with_timeout "$deep_max_time" copilot-relay status --deep >/dev/null 2>&1 || rc=$?
  return "$rc"
}

# ---------------------------------------------------------------- tier 1
# Liveness. Runs every invocation. A dead process is caught here, cheaply.

code="$(health_code)"
if [ "$code" != "200" ]; then
  log "copilot-relay unhealthy: GET $url -> ${code:-no_response}; restarting ${label}"
  if kickstart_relay; then
    if wait_for_health; then
      log "copilot-relay recovered: GET $url -> 200"
    else
      log "copilot-relay still unhealthy after restart: GET $url -> $(health_code)"
    fi
  fi
  cap_log
  exit 0
fi

# ---------------------------------------------------------------- tier 2
# Deep. Only reached when the socket is already answering 200, so this is
# strictly about whether Copilot is reachable through the relay.

deep_due || { cap_log; exit 0; }

# Stamp before running, not after: a deep check that fails or hangs must not
# retry every 60s and burn tokens.
: >"$deep_stamp"

deep_rc=0
deep_status || deep_rc=$?

case "$deep_rc" in
  0)
    cap_log
    exit 0
    ;;
  1)
    log "copilot-relay deep check: not running; restarting ${label}"
    ;;
  2)
    log "copilot-relay deep check: listening but cannot reach Copilot (likely expired auth — run 'copilot-relay auth' if this repeats); restarting ${label}"
    ;;
  124)
    log "copilot-relay deep check: timed out after ${deep_max_time}s; restarting ${label}"
    ;;
  *)
    log "copilot-relay deep check: exit ${deep_rc}; restarting ${label}"
    ;;
esac

if kickstart_relay; then
  if wait_for_health; then
    recheck_rc=0
    deep_status || recheck_rc=$?
    if [ "$recheck_rc" -eq 0 ]; then
      log "copilot-relay recovered: deep check passed"
    else
      log "copilot-relay still cannot reach Copilot after restart (status --deep -> ${recheck_rc}); run 'copilot-relay auth'"
    fi
  else
    log "copilot-relay still unhealthy after restart: GET $url -> $(health_code)"
  fi
fi

cap_log
exit 0
