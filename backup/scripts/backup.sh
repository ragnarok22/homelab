#!/bin/sh
# Homelab backup service
#
# Daily: dumps PostgreSQL databases, tars Docker volumes, service configs,
#        .env files, and Nginx Proxy Manager data.
# Weekly: optionally includes Immich library via rsync.
# Cloud: optionally syncs to Google Drive via rclone.

set -eu

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [backup] $1"
}

notify() {
  local title="$1"
  local message="$2"
  local priority="${3:-default}"
  local tags="${4:-}"

  curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${tags}" \
    -d "${message}" \
    "${NTFY_URL}/${NTFY_TOPIC}" > /dev/null 2>&1 || log "WARNING: Failed to send notification"
}

# --- Database backup ---
dump_pg() {
  local container="$1"
  local user="$2"
  local db="$3"
  local outfile="$4"

  log "Dumping ${container}/${db}"
  local tmpraw="${outfile%.gz}.tmp"

  # Dump to raw SQL first so we can check docker exec's exit code directly.
  # Piping through gzip would mask a pg_dump failure.
  if ! docker exec "${container}" pg_dump -U "${user}" -d "${db}" > "${tmpraw}" 2>&1; then
    log "ERROR: pg_dump failed for ${container}/${db}"
    # Log first lines of output for diagnostics (may contain the error message)
    head -5 "${tmpraw}" 2>/dev/null | while read -r line; do log "  pg_dump: ${line}"; done
    rm -f "${tmpraw}"
    return 1
  fi

  # A valid pg_dump always produces a header comment; reject trivially small dumps
  local size
  size=$(wc -c < "${tmpraw}" 2>/dev/null || echo 0)
  if [ "$size" -lt 20 ]; then
    log "ERROR: pg_dump produced empty output for ${container}/${db}"
    rm -f "${tmpraw}"
    return 1
  fi

  gzip -c "${tmpraw}" > "${outfile}" && rm -f "${tmpraw}"
}

backup_databases() {
  local dest="$1/databases"
  mkdir -p "$dest"
  local failed=0

  # Shared PostgreSQL
  if docker ps --format '{{.Names}}' | grep -q "^${PG_CONTAINER}$"; then
    OLD_IFS="$IFS"; IFS=','
    for db in ${PG_DATABASES}; do
      dump_pg "${PG_CONTAINER}" "${PG_USER}" "${db}" "${dest}/${PG_CONTAINER}_${db}.sql.gz" || failed=1
    done
    IFS="$OLD_IFS"
  else
    log "WARNING: Container ${PG_CONTAINER} not running, skipping"
    failed=1
  fi

  # Immich PostgreSQL
  if docker ps --format '{{.Names}}' | grep -q "^${IMMICH_PG_CONTAINER}$"; then
    OLD_IFS="$IFS"; IFS=','
    for db in ${IMMICH_PG_DATABASES}; do
      dump_pg "${IMMICH_PG_CONTAINER}" "${IMMICH_PG_USER}" "${db}" "${dest}/${IMMICH_PG_CONTAINER}_${db}.sql.gz" || failed=1
    done
    IFS="$OLD_IFS"
  else
    log "WARNING: Container ${IMMICH_PG_CONTAINER} not running, skipping"
    failed=1
  fi

  return $failed
}

# --- Named Docker volumes ---
backup_volumes() {
  local dest="$1/volumes"
  mkdir -p "$dest"

  OLD_IFS="$IFS"; IFS=','
  for vol in ${BACKUP_VOLUMES}; do
    if docker volume inspect "${vol}" > /dev/null 2>&1; then
      log "Backing up volume: ${vol}"
      docker run --rm \
        -v "${vol}:/volume:ro" \
        -v "${dest}:/backup" \
        alpine:3.20 tar czf "/backup/${vol}.tar.gz" -C /volume . 2>/dev/null
    else
      log "WARNING: Volume ${vol} not found, skipping"
    fi
  done
  IFS="$OLD_IFS"
}

# --- Service configs (bind mounts) ---
backup_configs() {
  local dest="$1/configs"
  mkdir -p "$dest"
  local failed=0

  OLD_IFS="$IFS"; IFS=','
  for svc in ${BACKUP_SERVICES}; do
    svc_dir="${HOMELAB_DIR}/${svc}"
    if [ ! -d "${svc_dir}" ]; then
      continue
    fi

    log "Backing up config for: ${svc}"
    mkdir -p "${dest}/${svc}"

    for subdir in config data appdata cache letsencrypt esphome grafana influxdb influxdb2 telegraf adb-keys; do
      if [ -d "${svc_dir}/${subdir}" ]; then
        if ! tar czf "${dest}/${svc}/${subdir}.tar.gz" -C "${svc_dir}" "${subdir}" 2>&1; then
          log "ERROR: Failed to archive ${svc}/${subdir}"
          failed=1
        fi
      fi
    done
  done
  IFS="$OLD_IFS"

  return $failed
}

# --- Env files ---
# When cloud backup is enabled, env files are stored as an encrypted tar archive
# to prevent secrets from being uploaded in plaintext.
backup_env_files() {
  local dest="$1/env-files"
  mkdir -p "$dest"

  find "${HOMELAB_DIR}" -maxdepth 2 -name ".env" -type f 2>/dev/null | while read -r envfile; do
    svc=$(basename "$(dirname "$envfile")")
    log "Backing up .env for: ${svc}"
    cp "$envfile" "${dest}/${svc}.env"
  done

  # If cloud backup is enabled, create an encrypted archive of env files
  if [ "${CLOUD_BACKUP_ENABLED}" = "true" ] && [ -n "${ENV_ENCRYPTION_KEY:-}" ]; then
    log "Encrypting env-files for cloud upload"
    tar cz -C "$dest" . | openssl enc -aes-256-cbc -salt -pbkdf2 \
      -pass "pass:${ENV_ENCRYPTION_KEY}" \
      -out "${dest}/env-files.tar.gz.enc" 2>/dev/null
    # Remove plaintext copies from the directory that gets synced to cloud
    # The plaintext copies remain in the local backup (separate directory)
  fi
}

# --- Immich library (weekly only, optional) ---
backup_immich_library() {
  local dest="$1"

  if [ "${BACKUP_IMMICH_LIBRARY}" != "true" ]; then
    return
  fi

  immich_lib="${HOMELAB_DIR}/immich/library"
  if [ ! -d "$immich_lib" ]; then
    log "WARNING: Immich library not found at ${immich_lib}"
    return
  fi

  log "Backing up Immich library (this may take a long time)"

  # Use hardlinks to previous weekly backup for space efficiency
  prev_weekly=$(ls -1d "${BACKUP_DIR}/weekly/"*/ 2>/dev/null | sort -r | head -1) || true
  if [ -n "$prev_weekly" ] && [ -d "${prev_weekly}/immich-library" ]; then
    rsync -a --link-dest="${prev_weekly}/immich-library" "${immich_lib}/" "${dest}/immich-library/"
  else
    rsync -a "${immich_lib}/" "${dest}/immich-library/"
  fi
}

# --- Manifest ---
write_manifest() {
  local dest="$1"
  local backup_type="$2"

  local db_list=""
  if [ -d "${dest}/databases" ]; then
    db_list=$(ls -1 "${dest}/databases/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi

  local vol_list=""
  if [ -d "${dest}/volumes" ]; then
    vol_list=$(ls -1 "${dest}/volumes/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi

  local svc_list=""
  if [ -d "${dest}/configs" ]; then
    svc_list=$(ls -1 "${dest}/configs/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi

  local total_size
  total_size=$(du -sh "${dest}" | cut -f1)

  cat > "${dest}/manifest.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "${backup_type}",
  "databases": "${db_list}",
  "volumes": "${vol_list}",
  "services": "${svc_list}",
  "size": "${total_size}"
}
EOF
}

# --- Retention cleanup ---
cleanup_old_backups() {
  local backup_type="$1"
  local keep_count="$2"
  local dir="${BACKUP_DIR}/${backup_type}"

  if [ ! -d "$dir" ]; then
    return
  fi

  count=$(ls -1d "${dir}/"*/ 2>/dev/null | wc -l)
  if [ "$count" -gt "$keep_count" ]; then
    remove_count=$((count - keep_count))
    ls -1d "${dir}/"*/ | sort | head -n "$remove_count" | while read -r old_dir; do
      log "Removing old backup: ${old_dir}"
      rm -rf "$old_dir"
    done
  fi
}

# --- Cloud sync ---
sync_to_cloud() {
  local backup_type="$1"
  local backup_path="$2"

  if [ "${CLOUD_BACKUP_ENABLED}" != "true" ]; then
    return 0
  fi

  log "Syncing to ${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${backup_type}/"

  # Always exclude plaintext .env files from cloud upload.
  # If an encryption key is set, the encrypted archive (env-files.tar.gz.enc) is uploaded instead.
  # If no key is set, env files are only available in the local backup.
  if [ -z "${ENV_ENCRYPTION_KEY:-}" ]; then
    log "WARNING: ENV_ENCRYPTION_KEY not set — .env files will NOT be uploaded to cloud"
  fi

  rclone copy "${backup_path}" \
    "${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${backup_type}/$(basename "${backup_path}")" \
    --transfers 4 \
    --checkers 8 \
    --exclude "env-files/*.env" \
    ${RCLONE_BWLIMIT:+--bwlimit "${RCLONE_BWLIMIT}"} \
    --log-level NOTICE 2>&1 || {
      notify "Cloud Backup FAILED" "Failed to sync ${backup_type} to ${RCLONE_REMOTE}" "high" "warning"
      return 1
    }

  # Clean old backups in cloud
  rclone delete "${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${backup_type}" \
    --min-age "${CLOUD_RETENTION_DAYS}d" 2>&1 || true
  rclone rmdirs "${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${backup_type}" \
    --leave-root 2>&1 || true

  log "Cloud sync complete"
}

# --- Run backup ---
run_backup() {
  local backup_type="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d_%H%M%S')
  local dest="${BACKUP_DIR}/${backup_type}/${timestamp}"

  mkdir -p "$dest"
  log "=== Starting ${backup_type} backup: ${dest} ==="

  local errors=""
  local start_time
  start_time=$(date +%s)

  backup_databases "$dest" || errors="${errors}- Database backup failed\n"
  backup_volumes "$dest" || errors="${errors}- Volume backup failed\n"
  backup_configs "$dest" || errors="${errors}- Config backup failed\n"
  backup_env_files "$dest" || errors="${errors}- Env file backup failed\n"

  if [ "$backup_type" = "weekly" ]; then
    backup_immich_library "$dest" || errors="${errors}- Immich library backup failed\n"
  fi

  write_manifest "$dest" "$backup_type"
  cleanup_old_backups "$backup_type" "$([ "$backup_type" = "weekly" ] && echo "${RETENTION_WEEKLY}" || echo "${RETENTION_DAILY}")"

  # Cloud sync
  local cloud_status=""
  if [ "${CLOUD_BACKUP_ENABLED}" = "true" ]; then
    if sync_to_cloud "$backup_type" "$dest"; then
      cloud_status=" | Cloud: OK"
    else
      cloud_status=" | Cloud: FAILED"
      errors="${errors}- Cloud sync failed\n"
    fi
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$(( end_time - start_time ))
  local size
  size=$(du -sh "$dest" | cut -f1)

  if [ -n "$errors" ]; then
    notify "Backup Completed with Errors" "${backup_type} backup (${size}, ${duration}s)${cloud_status}\n\nErrors:\n${errors}" "high" "warning"
  else
    notify "Backup Successful" "${backup_type} backup completed (${size}, ${duration}s)${cloud_status}" "default" "white_check_mark"
  fi

  log "=== ${backup_type} backup complete (${size}, ${duration}s)${cloud_status} ==="
}

# --- Scheduler ---
log "Backup service starting"
log "Schedule: daily at ${DAILY_BACKUP_TIME}, weekly on day ${WEEKLY_BACKUP_DAY}"
log "Retention: ${RETENTION_DAILY} daily, ${RETENTION_WEEKLY} weekly"
log "Cloud: ${CLOUD_BACKUP_ENABLED}"

while true; do
  current_time=$(date '+%H:%M')
  current_dow=$(date '+%w')

  if [ "$current_time" = "${DAILY_BACKUP_TIME}" ]; then
    if [ "$current_dow" = "${WEEKLY_BACKUP_DAY}" ]; then
      run_backup "weekly"
    fi
    run_backup "daily"
    # Sleep past the trigger minute
    sleep 120
  fi

  sleep 30
done
