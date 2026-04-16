#!/bin/sh
# Disk health monitor
#
# Checks SMART data for NVMe and HDD, disk space usage,
# and dmesg for I/O errors. Sends alerts via ntfy.sh.
# Uses state files to avoid duplicate notifications.

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

check_nvme() {
  if [ -z "${NVME_DEVICE:-}" ]; then
    return
  fi

  log "Checking NVMe: ${NVME_DEVICE}"

  smart_json=$(smartctl -a "${NVME_DEVICE}" --json=c 2>/dev/null) || {
    notify_dedup "nvme_read_fail" "Disk Monitor ALERT" "Failed to read SMART data from ${NVME_DEVICE}" "urgent" "warning"
    return
  }
  clear_alert "nvme_read_fail"

  temperature=$(echo "$smart_json" | jq -r '.temperature.current // empty')
  media_errors=$(echo "$smart_json" | jq -r '.nvme_smart_health_information_log.media_errors // 0')
  percentage_used=$(echo "$smart_json" | jq -r '.nvme_smart_health_information_log.percentage_used // 0')
  critical_warning=$(echo "$smart_json" | jq -r '.nvme_smart_health_information_log.critical_warning // 0')
  available_spare=$(echo "$smart_json" | jq -r '.nvme_smart_health_information_log.available_spare // 100')
  power_on_hours=$(echo "$smart_json" | jq -r '.nvme_smart_health_information_log.power_on_hours // 0')

  log "  temp=${temperature}C media_errors=${media_errors} used=${percentage_used}% spare=${available_spare}% hours=${power_on_hours}"

  alerts=""

  if [ "$critical_warning" -ne 0 ] 2>/dev/null; then
    alerts="${alerts}CRITICAL: NVMe critical warning flag is ${critical_warning}\n"
  fi

  if [ "$media_errors" -gt 0 ] 2>/dev/null; then
    alerts="${alerts}WARNING: NVMe has ${media_errors} media error(s)\n"
  fi

  if [ -n "$temperature" ] && [ "$temperature" -ge "${NVME_TEMP_WARN}" ] 2>/dev/null; then
    alerts="${alerts}WARNING: NVMe temperature is ${temperature}C (threshold: ${NVME_TEMP_WARN}C)\n"
  fi

  if [ "$percentage_used" -ge 90 ] 2>/dev/null; then
    alerts="${alerts}CRITICAL: NVMe wear level at ${percentage_used}%\n"
  elif [ "$percentage_used" -ge 80 ] 2>/dev/null; then
    alerts="${alerts}WARNING: NVMe wear level at ${percentage_used}%\n"
  fi

  if [ "$available_spare" -le 10 ] 2>/dev/null; then
    alerts="${alerts}CRITICAL: NVMe available spare at ${available_spare}%\n"
  fi

  if [ -n "$alerts" ]; then
    notify_dedup "nvme_health" "NVMe Health Alert" "$(printf '%b' "$alerts")" "high" "warning"
  else
    clear_alert "nvme_health"
  fi
}

check_hdd() {
  if [ -z "${HDD_DEVICE:-}" ]; then
    return
  fi

  log "Checking HDD: ${HDD_DEVICE}"

  smart_json=$(smartctl -a "${HDD_DEVICE}" --json=c 2>/dev/null) || {
    notify_dedup "hdd_read_fail" "Disk Monitor ALERT" "Failed to read SMART data from ${HDD_DEVICE}" "urgent" "warning"
    return
  }
  clear_alert "hdd_read_fail"

  temperature=$(echo "$smart_json" | jq -r '.temperature.current // empty')
  reallocated=$(echo "$smart_json" | jq -r '[.ata_smart_attributes.table[] | select(.id == 5)] | .[0].raw.value // 0')
  pending_sectors=$(echo "$smart_json" | jq -r '[.ata_smart_attributes.table[] | select(.id == 197)] | .[0].raw.value // 0')
  uncorrectable=$(echo "$smart_json" | jq -r '[.ata_smart_attributes.table[] | select(.id == 198)] | .[0].raw.value // 0')
  power_on_hours=$(echo "$smart_json" | jq -r '[.ata_smart_attributes.table[] | select(.id == 9)] | .[0].raw.value // 0')
  smart_passed=$(echo "$smart_json" | jq -r '.smart_status.passed // true')

  log "  temp=${temperature}C reallocated=${reallocated} pending=${pending_sectors} uncorrectable=${uncorrectable} hours=${power_on_hours}"

  alerts=""

  if [ "$smart_passed" = "false" ]; then
    alerts="${alerts}CRITICAL: HDD SMART overall assessment FAILED\n"
  fi

  if [ "$reallocated" -gt 0 ] 2>/dev/null; then
    alerts="${alerts}WARNING: HDD has ${reallocated} reallocated sector(s)\n"
  fi

  if [ "$pending_sectors" -gt 0 ] 2>/dev/null; then
    alerts="${alerts}WARNING: HDD has ${pending_sectors} pending sector(s)\n"
  fi

  if [ "$uncorrectable" -gt 0 ] 2>/dev/null; then
    alerts="${alerts}WARNING: HDD has ${uncorrectable} uncorrectable error(s)\n"
  fi

  if [ -n "$temperature" ] && [ "$temperature" -ge "${HDD_TEMP_WARN}" ] 2>/dev/null; then
    alerts="${alerts}WARNING: HDD temperature is ${temperature}C (threshold: ${HDD_TEMP_WARN}C)\n"
  fi

  if [ -n "$alerts" ]; then
    notify_dedup "hdd_health" "HDD Health Alert" "$(printf '%b' "$alerts")" "high" "warning"
  else
    clear_alert "hdd_health"
  fi
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
    # Hash the actual error lines so we only re-alert when new errors appear
    notify_dedup "dmesg_io" "Disk I/O Errors Detected" "Recent kernel I/O errors:\n${errors}" "high" "warning"
  else
    clear_alert "dmesg_io"
  fi
}

# --- Main loop ---
log "Disk monitor starting (interval: ${CHECK_INTERVAL}s)"
log "NVMe: ${NVME_DEVICE:-none} | HDD: ${HDD_DEVICE:-none}"
log "Thresholds: NVMe temp>=${NVME_TEMP_WARN}C, HDD temp>=${HDD_TEMP_WARN}C, space>=${DISK_USAGE_WARN}%/${DISK_USAGE_CRITICAL}%"

while true; do
  log "=== Starting health check ==="

  check_nvme
  check_hdd
  check_disk_space
  check_dmesg_errors

  log "=== Health check complete. Next in ${CHECK_INTERVAL}s ==="
  sleep "${CHECK_INTERVAL}"
done
