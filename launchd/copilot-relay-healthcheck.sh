#!/usr/bin/env bash
set -euo pipefail

# launchd watchdog for copilot-relay. It checks the local health endpoint and
# only restarts the relay agent when the HTTP service does not respond healthy.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

label="${COPILOT_RELAY_LABEL:-com.d0n9x1n.copilot-relay}"
url="${COPILOT_RELAY_HEALTH_URL:-http://127.0.0.1:4142/healthz}"
plist="${COPILOT_RELAY_PLIST:-${HOME}/Library/LaunchAgents/${label}.plist}"
log_file="${COPILOT_RELAY_HEALTH_LOG:-${HOME}/Library/Logs/copilot-relay-healthcheck.log}"
log_max_lines="${COPILOT_RELAY_HEALTH_LOG_MAX_LINES:-500}"
connect_timeout="${COPILOT_RELAY_HEALTH_CONNECT_TIMEOUT:-1}"
max_time="${COPILOT_RELAY_HEALTH_MAX_TIME:-3}"
uid="$(id -u)"

mkdir -p "$(dirname "$log_file")"

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

health_code() {
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl-missing'
    return 0
  fi
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

code="$(health_code)"
if [ "$code" = "200" ]; then
  cap_log
  exit 0
fi

log "copilot-relay unhealthy: GET $url -> ${code:-no_response}; restarting ${label}"

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
  cap_log
  exit 0
fi

if wait_for_health; then
  log "copilot-relay recovered: GET $url -> 200"
else
  log "copilot-relay still unhealthy after restart: GET $url -> $(health_code)"
fi

cap_log
exit 0
