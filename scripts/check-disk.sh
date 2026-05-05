#!/bin/bash
# Disk usage alert for cron. Reads optional settings from scripts/alerts.env.

set -euo pipefail

HOMELAB_DIR="${HOMELAB_DIR:-/root/homelab}"
ALERTS_ENV="${ALERTS_ENV:-${HOMELAB_DIR}/scripts/alerts.env}"

if [ -f "$ALERTS_ENV" ]; then
  # shellcheck disable=SC1090
  . "$ALERTS_ENV"
fi

THRESHOLD="${DISK_ALERT_THRESHOLD:-90}"
STATE_FILE="${DISK_ALERT_STATE_FILE:-/tmp/homelab-disk-alert.state}"

if [ "$#" -gt 0 ]; then
  MOUNT_PATHS=("$1")
elif [ -n "${DISK_CHECK_PATHS:-}" ]; then
  # Space-separated list, for example: DISK_CHECK_PATHS="/ /home/Data".
  read -r -a MOUNT_PATHS <<< "$DISK_CHECK_PATHS"
elif [ -n "${DISK_CHECK_PATH:-}" ]; then
  MOUNT_PATHS=("$DISK_CHECK_PATH")
else
  MOUNT_PATHS=("/" "/home/Data")
fi

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

  if ! curl "${curl_args[@]}" --data-binary "$message" "$endpoint" >/dev/null; then
    log "WARNING: failed to send ntfy notification"
  fi
}

push_kuma() {
  local status="$1" msg="$2"

  if [ -z "${KUMA_DISK_PUSH_URL:-}" ] || ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsS -m "${KUMA_TIMEOUT:-10}" "${KUMA_DISK_PUSH_URL}?status=${status}&msg=${msg}&ping=" >/dev/null || \
    log "WARNING: failed to push disk status to Uptime Kuma"
}

state_file_for_mount() {
  local mount_path="$1"

  if [ "${#MOUNT_PATHS[@]}" -eq 1 ]; then
    printf '%s\n' "$STATE_FILE"
    return 0
  fi

  local suffix
  suffix=$(printf '%s' "$mount_path" | tr -c '[:alnum:]_.-' '_')
  printf '%s.%s\n' "$STATE_FILE" "$suffix"
}

check_mount() {
  local mount_path="$1"
  local state_file usage_output available_output usage available

  state_file="$(state_file_for_mount "$mount_path")"
  if ! usage_output=$(df -P "$mount_path"); then
    log "ERROR: unable to read disk usage for ${mount_path}"
    notify_ntfy "Disk check failed" "high" "warning" "Could not read disk usage for ${mount_path}."
    return 2
  fi
  if ! available_output=$(df -h "$mount_path"); then
    log "ERROR: unable to read available disk space for ${mount_path}"
    notify_ntfy "Disk check failed" "high" "warning" "Could not read available disk space for ${mount_path}."
    return 2
  fi

  usage=$(awk 'NR == 2 { gsub("%", "", $5); print $5 }' <<< "$usage_output")
  available=$(awk 'NR == 2 { print $4 }' <<< "$available_output")

  if [ -z "$usage" ]; then
    log "ERROR: unable to read disk usage for ${mount_path}"
    notify_ntfy "Disk check failed" "high" "warning" "Could not read disk usage for ${mount_path}."
    return 2
  fi

  if [ "$usage" -ge "$THRESHOLD" ]; then
    if [ "$(cat "$state_file" 2>/dev/null || true)" != "alert" ]; then
      notify_ntfy "Disk usage high" "high" "warning" "${mount_path} is ${usage}% full. Available: ${available}. Threshold: ${THRESHOLD}%."
      printf '%s\n' alert > "$state_file"
    fi
    log "ALERT: ${mount_path} is ${usage}% full; available ${available}"
    return 1
  fi

  if [ "$(cat "$state_file" 2>/dev/null || true)" = "alert" ]; then
    notify_ntfy "Disk usage recovered" "default" "white_check_mark" "${mount_path} is back below threshold at ${usage}% full. Available: ${available}."
    rm -f "$state_file"
  fi

  log "OK: ${mount_path} is ${usage}% full; available ${available}"
  return 0
}

failed=0
check_failed=0
for mount_path in "${MOUNT_PATHS[@]}"; do
  if check_mount "$mount_path"; then
    continue
  else
    mount_status=$?
    failed=1
    if [ "$mount_status" -eq 2 ]; then
      check_failed=1
    fi
  fi
done

if [ "$failed" -ne 0 ]; then
  if [ "$check_failed" -ne 0 ]; then
    push_kuma down disk-check-failed
  else
    push_kuma down disk-full
  fi
  exit 1
fi

push_kuma up disk-ok
