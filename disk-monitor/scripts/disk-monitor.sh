#!/bin/sh
# Disk space and I/O error monitor
#
# Checks host disk space usage and dmesg for I/O errors.
# SMART monitoring is handled by Scrutiny — this script covers
# what Scrutiny does not: filesystem usage and kernel I/O errors.
# Sends alerts via ntfy.sh with deduplication.

set -eu

STATE_DIR="/tmp/disk-monitor-state"
mkdir -p "$STATE_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

notify() {
  local title="$1"
  local message="$2"
  local priority="${3:-default}"
  local tags="${4:-}"

  if curl -sf \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${tags}" \
    -d "${message}" \
    "${NTFY_URL}/${NTFY_TOPIC}" > /dev/null 2>&1; then
    return 0
  else
    log "WARNING: Failed to send notification"
    return 1
  fi
}

# Send notification only if the alert state has changed.
# Only marks the alert as sent if delivery actually succeeded.
notify_dedup() {
  local key="$1"
  local title="$2"
  local message="$3"
  local priority="${4:-default}"
  local tags="${5:-}"

  local state_file="${STATE_DIR}/${key}"
  local current_hash
  current_hash=$(printf '%s' "$message" | md5sum | cut -d' ' -f1)

  if [ -f "$state_file" ] && [ "$(cat "$state_file")" = "$current_hash" ]; then
    log "  (dedup: skipping already-sent alert for ${key})"
    return
  fi

  if notify "$title" "$message" "$priority" "$tags"; then
    printf '%s' "$current_hash" > "$state_file"
  fi
}

# Clear alert state when condition resolves
clear_alert() {
  local key="$1"
  rm -f "${STATE_DIR}/${key}"
}

check_disk_space() {
  log "Checking disk space (host filesystems via /host)"

  grep -E '^/dev/' /host/proc/mounts 2>/dev/null | awk '{print $2}' | sort -u | while read -r mount; do
    host_path="/host${mount}"
    [ -d "$host_path" ] || continue

    line=$(df -P "$host_path" 2>/dev/null | tail -1) || continue
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    avail=$(echo "$line" | awk '{print $4}')
    [ -n "$pct" ] || continue

    avail_h=$(echo "$avail" | awk '{
      if ($1 >= 1073741824) printf "%.1fT", $1/1073741824;
      else if ($1 >= 1048576) printf "%.1fG", $1/1048576;
      else if ($1 >= 1024) printf "%.0fM", $1/1024;
      else printf "%dK", $1
    }')

    log "  ${mount}: ${pct}% used (${avail_h} free)"

    # Sanitize mount for use as state key
    mount_key=$(printf '%s' "$mount" | tr '/' '_')

    if [ "$pct" -ge "${DISK_USAGE_CRITICAL}" ] 2>/dev/null; then
      notify_dedup "space_crit_${mount_key}" "Disk Space CRITICAL" "${mount} is ${pct}% full (${avail_h} remaining)" "urgent" "warning"
    elif [ "$pct" -ge "${DISK_USAGE_WARN}" ] 2>/dev/null; then
      notify_dedup "space_warn_${mount_key}" "Disk Space Warning" "${mount} is ${pct}% full (${avail_h} remaining)" "high" "warning"
      clear_alert "space_crit_${mount_key}"
    else
      clear_alert "space_warn_${mount_key}"
      clear_alert "space_crit_${mount_key}"
    fi
  done
}

check_dmesg_errors() {
  log "Checking dmesg for I/O errors"

  errors=$(dmesg 2>/dev/null | grep -i -E "I/O error|medium error|blk_update_request.*error|ata.*error|nvme.*error|nvme.*timeout|EXT4-fs error" | tail -5) || true

  if [ -n "$errors" ]; then
    notify_dedup "dmesg_io" "Disk I/O Errors Detected" "Recent kernel I/O errors:\n${errors}" "high" "warning"
  else
    clear_alert "dmesg_io"
  fi
}

# --- Main loop ---
log "Disk monitor starting (interval: ${CHECK_INTERVAL}s)"
log "SMART monitoring delegated to Scrutiny"
log "Thresholds: space>=${DISK_USAGE_WARN}%/${DISK_USAGE_CRITICAL}%"

while true; do
  log "=== Starting health check ==="

  check_disk_space
  check_dmesg_errors

  log "=== Health check complete. Next in ${CHECK_INTERVAL}s ==="
  sleep "${CHECK_INTERVAL}"
done
