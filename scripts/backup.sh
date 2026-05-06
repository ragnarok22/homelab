#!/bin/bash
# Daily backup script — runs via cron at 01:00, Duplicati picks up at 02:00.
#
# What it backs up:
#   - PostgreSQL: immich_postgres (immich db), postgres (n8n db)
#   - MySQL: invoice-ninja-db (ninja db)
#   - Service config/data dirs from HOMELAB_DIR
#   - Named Docker volumes (n8n data, pgAdmin config)
#
# Output: BACKUP_ROOT/YYYY-MM-DD_HHMMSS/
# Local retention: KEEP_DAYS (Duplicati handles long-term via versioning)

set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/home/Data/backup_homelab}"
BACKUP_STAGING_ROOT="${BACKUP_STAGING_ROOT:-$(dirname "$BACKUP_ROOT")/.backup_homelab_staging}"
HOMELAB_DIR="${HOMELAB_DIR:-/root/homelab}"
KEEP_DAYS="${KEEP_DAYS:-7}"
LOCK_FILE="${BACKUP_LOCK_FILE:-/var/lock/homelab-backup.lock}"
COMMAND_TIMEOUT_SECONDS="${BACKUP_COMMAND_TIMEOUT_SECONDS:-1800}"
ARCHIVE_TIMEOUT_SECONDS="${BACKUP_ARCHIVE_TIMEOUT_SECONDS:-1800}"
MAX_SECONDS="${BACKUP_MAX_SECONDS:-5400}"
KILL_AFTER_SECONDS="${BACKUP_KILL_AFTER_SECONDS:-60}"
PG_DUMP_LOCK_TIMEOUT="${PG_DUMP_LOCK_TIMEOUT:-5min}"
ALERTS_ENV="${ALERTS_ENV:-${HOMELAB_DIR}/scripts/alerts.env}"

DATE=$(date '+%Y-%m-%d_%H%M%S')
DEST="${BACKUP_STAGING_ROOT}/${DATE}"
FINAL_DEST="${BACKUP_ROOT}/${DATE}"
ERRORS=0

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [backup] $*"; }

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

if [ -n "$TIMEOUT_BIN" ] && [ -z "${BACKUP_GLOBAL_TIMEOUT_ACTIVE:-}" ]; then
  export BACKUP_GLOBAL_TIMEOUT_ACTIVE=1
  exec "$TIMEOUT_BIN" --preserve-status --kill-after="${KILL_AFTER_SECONDS}s" "${MAX_SECONDS}s" "$0" "$@"
fi

if [ -f "$ALERTS_ENV" ]; then
  # shellcheck disable=SC1090
  . "$ALERTS_ENV"
fi

lock_dir="$(dirname "$LOCK_FILE")"
mkdir -p "$lock_dir" 2>/dev/null || true
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  if ! flock -n 9; then
    log "ERROR: another backup is already running; refusing to start"
    exit 1
  fi
else
  log "WARNING: flock not found; backup concurrency lock is disabled"
fi

run_limited() {
  local seconds="$1"
  shift

  local cmd=()
  if command -v ionice >/dev/null 2>&1; then
    cmd+=(ionice -c2 -n7)
  fi
  if command -v nice >/dev/null 2>&1; then
    cmd+=(nice -n 19)
  fi
  cmd+=("$@")

  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" --kill-after="${KILL_AFTER_SECONDS}s" "${seconds}s" "${cmd[@]}"
  else
    log "WARNING: timeout command not found; running without per-command timeout: $*"
    "${cmd[@]}"
  fi
}

cleanup_staging() {
  [ -n "${DEST:-}" ] || return 0
  [ -d "$DEST" ] || return 0
  find "$DEST" -type f -name "*.tmp" -delete 2>/dev/null || true
  rm -rf "$DEST"
}

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

  if [ -z "${KUMA_BACKUP_PUSH_URL:-}" ] || ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsS -m "${KUMA_TIMEOUT:-10}" "${KUMA_BACKUP_PUSH_URL}?status=${status}&msg=${msg}&ping=" >/dev/null 2>&1 || \
    log "WARNING: failed to push backup status to Uptime Kuma"
}

finish() {
  local exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    cleanup_staging
    push_kuma down backup-failed
    notify_ntfy "Backup failed" "urgent" "warning" "Homelab backup failed on $(hostname). Destination: ${FINAL_DEST}. Errors recorded: ${ERRORS}."
    exit "$exit_code"
  fi

  if [ -e "$FINAL_DEST" ]; then
    log "ERROR: final destination already exists: ${FINAL_DEST}"
    cleanup_staging
    push_kuma down backup-failed
    notify_ntfy "Backup failed" "urgent" "warning" "Homelab backup failed on $(hostname). Destination already exists: ${FINAL_DEST}."
    exit 1
  fi

  touch "${DEST}/.complete"
  mv "$DEST" "$FINAL_DEST"

  push_kuma up backup-ok
  if [ "${NTFY_NOTIFY_SUCCESS:-false}" = "true" ]; then
    notify_ntfy "Backup complete" "default" "white_check_mark" "Homelab backup completed on $(hostname). Destination: ${FINAL_DEST}."
  fi
  exit 0
}

trap finish EXIT

mkdir -p "$BACKUP_ROOT" "$BACKUP_STAGING_ROOT"
find "$BACKUP_STAGING_ROOT" -maxdepth 1 -type d -name "????-??-??_*" -mtime +1 -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$DEST"
log "=== Starting backup: ${FINAL_DEST} ==="

# --- PostgreSQL dumps ---
dump_pg() {
  local container="$1" user="$2" db="$3"
  local outfile="${DEST}/databases/${container}__${db}.sql.gz"
  log "Dumping postgres: ${container}/${db}"
  local tmp="${outfile}.tmp"
  if run_limited "$COMMAND_TIMEOUT_SECONDS" docker exec "$container" sh -c "pg_dump --lock-wait-timeout='${PG_DUMP_LOCK_TIMEOUT}' -U '$user' '$db'" | run_limited "$COMMAND_TIMEOUT_SECONDS" gzip -1 > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$outfile"
  else
    rm -f "$tmp"
    log "ERROR: pg_dump failed for ${container}/${db}"
    ERRORS=$((ERRORS + 1))
  fi
}

mkdir -p "${DEST}/databases"
dump_pg "immich_postgres" "postgres" "immich"
dump_pg "postgres"        "postgres" "n8n"

# --- MySQL dump (Invoice Ninja) ---
log "Dumping mysql: invoice-ninja-db/ninja"
tmp="${DEST}/databases/invoice-ninja-db__ninja.sql.gz.tmp"
if run_limited "$COMMAND_TIMEOUT_SECONDS" docker exec invoice-ninja-db sh -c "mysqldump -uroot -p\"\$MYSQL_ROOT_PASSWORD\" --single-transaction --set-gtid-purged=OFF ninja" | run_limited "$COMMAND_TIMEOUT_SECONDS" gzip -1 > "$tmp" && [ -s "$tmp" ]; then
  mv "$tmp" "${DEST}/databases/invoice-ninja-db__ninja.sql.gz"
else
  rm -f "$tmp"
  log "ERROR: mysqldump failed for invoice-ninja-db"
  ERRORS=$((ERRORS + 1))
fi

# --- Service config/data dirs ---
mkdir -p "${DEST}/configs"
SERVICES="cloudflared dash diun duplicati excalidraw homarr immich invoice-ninja jellyfin jellyseerr n8n nextcloud nginx-manager ntfy pgadmin prowlarr qbittorrents radarr sonarr suwayomi uptime-kuma watchtower"
for svc in $SERVICES; do
  svc_dir="${HOMELAB_DIR}/${svc}"
  [ -d "$svc_dir" ] || continue
  for subdir in config data appdata letsencrypt; do
    [ -d "${svc_dir}/${subdir}" ] || continue
    log "Archiving ${svc}/${subdir}"
    tmp="${DEST}/configs/${svc}_${subdir}.tar.gz.tmp"
    if run_limited "$ARCHIVE_TIMEOUT_SECONDS" tar czf "$tmp" -C "$svc_dir" "$subdir" 2>/dev/null; then
      mv "$tmp" "${DEST}/configs/${svc}_${subdir}.tar.gz"
    else
      rm -f "$tmp"
      log "WARNING: Failed to archive ${svc}/${subdir}"
    fi
  done
done

# --- Named Docker volumes ---
mkdir -p "${DEST}/volumes"
for vol in n8n_n8n_data pgadmin_pgadmin-data; do
  docker volume inspect "$vol" > /dev/null 2>&1 || continue
  log "Archiving volume: ${vol}"
  tmp="${DEST}/volumes/${vol}.tar.gz.tmp"
  if run_limited "$ARCHIVE_TIMEOUT_SECONDS" docker run --rm \
    -v "${vol}:/data:ro" \
    -v "${DEST}/volumes:/backup" \
    alpine:3.20 tar czf "/backup/${vol}.tar.gz.tmp" -C /data . 2>/dev/null; then
    mv "${DEST}/volumes/${vol}.tar.gz.tmp" "${DEST}/volumes/${vol}.tar.gz"
  else
    log "WARNING: Failed to archive volume ${vol}"
  fi
done

# --- Cleanup old backups ---
log "Pruning backups older than ${KEEP_DAYS} days"
run_limited 300 find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??_*" -mtime "+${KEEP_DAYS}" -exec rm -rf {} + 2>/dev/null || true

if [ "$ERRORS" -gt 0 ]; then
  log "=== Backup finished with ${ERRORS} error(s) ==="
  exit 1
else
  log "=== Backup complete ==="
fi
