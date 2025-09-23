#!/usr/bin/env bash
# Universal health check: HTTP(S) or TCP.
# Usage:
#   healthcheck.sh <endpoint> [delay_seconds]
#     endpoint: http(s)://host[:port][/path]  OR  host:port  OR  tcp://host:port
#     delay_seconds (optional): sleep between attempts (default: 5)
#
# Env vars:
#   MAX_ATTEMPTS   total tries before failing (default: 60)
#   TIMEOUT        per-attempt timeout seconds (default: 5)
#   STATUS_RANGE   HTTP range to consider healthy, e.g. 200-399 (default: 200-399)
#   CURL_INSECURE  set to 1 to ignore TLS cert errors for HTTPS (adds curl -k)
#   QUIET          set to 1 to suppress progress logs
#
# Exit codes:
#   0 = became healthy; non-zero = did not become healthy (Terraform will fail)

set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: healthcheck.sh <endpoint> [delay_seconds]
Endpoint formats:
  • http(s)://host[:port][/path]  (HTTP check against STATUS_RANGE)
  • host:port or tcp://host:port  (TCP connect check)

Env:
  MAX_ATTEMPTS (default 60), TIMEOUT (default 5), STATUS_RANGE (default 200-399)
  CURL_INSECURE=1 to skip TLS verification, QUIET=1 to reduce output
USAGE
}

log() { [[ "${QUIET:-0}" = "1" ]] || echo "[$(date +%H:%M:%S)] $*" >&2; }

endpoint="${1:-}"
delay="${2:-5}"
[[ -n "$endpoint" ]] || { usage; exit 2; }
[[ "$delay" =~ ^[0-9]+$ ]] || { echo "Delay must be integer seconds" >&2; exit 2; }

MAX_ATTEMPTS="${MAX_ATTEMPTS:-60}"
TIMEOUT="${TIMEOUT:-5}"
STATUS_RANGE="${STATUS_RANGE:-200-399}"

# Parse HTTP status range
if [[ "$STATUS_RANGE" =~ ^([0-9]{3})-([0-9]{3})$ ]]; then
  MIN_STATUS="${BASH_REMATCH[1]}"
  MAX_STATUS="${BASH_REMATCH[2]}"
else
  echo "Bad STATUS_RANGE '$STATUS_RANGE' (want NNN-NNN)" >&2
  exit 2
fi

is_http() { [[ "$endpoint" =~ ^https?:// ]]; }
strip_tcp_scheme() { echo "${endpoint#tcp://}"; }

http_probe() {
  local code
  local -a curl_opts=(-fsS -o /dev/null -m "$TIMEOUT" -w '%{http_code}')
  [[ "${CURL_INSECURE:-0}" = "1" ]] && curl_opts+=(-k)
  code="$(curl "${curl_opts[@]}" "$endpoint" || true)"
  [[ "$code" =~ ^[0-9]{3}$ ]] && (( code >= MIN_STATUS && code <= MAX_STATUS ))
}

tcp_probe() {
  local addr host port
  addr="$(strip_tcp_scheme)"
  host="${addr%:*}"
  port="${addr##*:}"
  if [[ -z "$host" || -z "$port" || "$host" = "$port" ]]; then
    echo "Bad TCP endpoint '$endpoint'. Use host:port or tcp://host:port" >&2
    return 2
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z -w "$TIMEOUT" "$host" "$port"
  else
    # Fallback to bash /dev/tcp, optionally wrapped with timeout if available
    if command -v timeout >/dev/null 2>&1; then
      timeout "$TIMEOUT" bash -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1
    else
      bash -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1
    fi
  fi
}

probe_once() {
  if is_http; then http_probe; else tcp_probe; fi
}

for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
  if probe_once; then
    log "Healthy: $endpoint"
    exit 0
  fi
  log "Not healthy yet (attempt $i/$MAX_ATTEMPTS). Sleeping ${delay}s…"
  sleep "$delay"
done

log "Gave up after $MAX_ATTEMPTS attempts. $endpoint is not healthy."
exit 1
