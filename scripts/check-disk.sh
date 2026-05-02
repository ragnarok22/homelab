#!/bin/bash
# Disk usage alert for cron. Reads optional settings from scripts/alerts.env.

set -euo pipefail

HOMELAB_DIR="${HOMELAB_DIR:-/root/homelab}"
ALERTS_ENV="${ALERTS_ENV:-${HOMELAB_DIR}/scripts/alerts.env}"

if [ -f "$ALERTS_ENV" ]; then
  # shellcheck disable=SC1090
  . "$ALERTS_ENV"
fi

MOUNT_PATH="${1:-${DISK_CHECK_PATH:-/home/Data}}"
THRESHOLD="${DISK_ALERT_THRESHOLD:-90}"
STATE_FILE="${DISK_ALERT_STATE_FILE:-/tmp/homelab-disk-alert.state}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [disk] $*"; }

notify_ntfy() {
  local title="$1" priority="$2" tags="$3" message="$4"

  if [ -z "${NTFY_URL:-}" ] || [ -z "${NTFY_TOPIC:-}" ]; then
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    log "WARNING: curl not found; cannot send ntfy notification"
    return 0
  fi

  local endpoint="${NTFY_URL%/}/${NTFY_TOPIC}"
  local curl_args=(-fsS -m "${NTFY_TIMEOUT:-10}" -H "Title: ${title}" -H "Priority: ${priority}" -H "Tags: ${tags}")
  if [ -n "${NTFY_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
  fi

  if ! curl "${curl_args[@]}" --data-binary "$message" "$endpoint" >/dev/null 2>&1; then
    log "WARNING: failed to send ntfy notification"
  fi
}

push_kuma() {
  local status="$1" msg="$2"

  if [ -z "${KUMA_DISK_PUSH_URL:-}" ] || ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsS -m "${KUMA_TIMEOUT:-10}" "${KUMA_DISK_PUSH_URL}?status=${status}&msg=${msg}&ping=" >/dev/null 2>&1 || \
    log "WARNING: failed to push disk status to Uptime Kuma"
}

usage=$(df -P "$MOUNT_PATH" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
available=$(df -h "$MOUNT_PATH" | awk 'NR == 2 { print $4 }')

if [ -z "$usage" ]; then
  log "ERROR: unable to read disk usage for ${MOUNT_PATH}"
  push_kuma down disk-check-failed
  notify_ntfy "Disk check failed" "high" "warning" "Could not read disk usage for ${MOUNT_PATH}."
  exit 1
fi

if [ "$usage" -ge "$THRESHOLD" ]; then
  push_kuma down disk-full
  if [ "$(cat "$STATE_FILE" 2>/dev/null || true)" != "alert" ]; then
    notify_ntfy "Disk usage high" "high" "warning" "${MOUNT_PATH} is ${usage}% full. Available: ${available}. Threshold: ${THRESHOLD}%."
    printf '%s\n' alert > "$STATE_FILE"
  fi
  log "ALERT: ${MOUNT_PATH} is ${usage}% full; available ${available}"
  exit 1
fi

push_kuma up disk-ok
if [ "$(cat "$STATE_FILE" 2>/dev/null || true)" = "alert" ]; then
  notify_ntfy "Disk usage recovered" "default" "white_check_mark" "${MOUNT_PATH} is back below threshold at ${usage}% full. Available: ${available}."
  rm -f "$STATE_FILE"
fi

log "OK: ${MOUNT_PATH} is ${usage}% full; available ${available}"
