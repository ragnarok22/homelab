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

BACKUP_ROOT="/home/Data/backup_homelab"
HOMELAB_DIR="/root/homelab"
KEEP_DAYS=7

DATE=$(date '+%Y-%m-%d_%H%M%S')
DEST="${BACKUP_ROOT}/${DATE}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [backup] $*"; }

mkdir -p "$DEST"
log "=== Starting backup: ${DEST} ==="
ERRORS=0

# --- PostgreSQL dumps ---
dump_pg() {
  local container="$1" user="$2" db="$3"
  local outfile="${DEST}/databases/${container}__${db}.sql.gz"
  log "Dumping postgres: ${container}/${db}"
  local tmp="${outfile}.tmp"
  if docker exec "$container" sh -c "pg_dump -U '$user' '$db'" | gzip > "$tmp" && [ -s "$tmp" ]; then
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
if docker exec invoice-ninja-db sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --set-gtid-purged=OFF ninja' | gzip > "$tmp" && [ -s "$tmp" ]; then
  mv "$tmp" "${DEST}/databases/invoice-ninja-db__ninja.sql.gz"
else
  rm -f "$tmp"
  log "ERROR: mysqldump failed for invoice-ninja-db"
  ERRORS=$((ERRORS + 1))
fi

# --- Service config/data dirs ---
mkdir -p "${DEST}/configs"
SERVICES="cloudflared dash duplicati excalidraw homarr immich invoice-ninja jellyfin jellyseerr n8n nextcloud nginx-manager pgadmin prowlarr qbittorrents radarr sonarr suwayomi watchtower"
for svc in $SERVICES; do
  svc_dir="${HOMELAB_DIR}/${svc}"
  [ -d "$svc_dir" ] || continue
  for subdir in config data appdata letsencrypt; do
    [ -d "${svc_dir}/${subdir}" ] || continue
    log "Archiving ${svc}/${subdir}"
    tmp="${DEST}/configs/${svc}_${subdir}.tar.gz.tmp"
    if tar czf "$tmp" -C "$svc_dir" "$subdir" 2>/dev/null; then
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
  if docker run --rm \
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
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??_*" -mtime "+${KEEP_DAYS}" -exec rm -rf {} + 2>/dev/null || true

if [ "$ERRORS" -gt 0 ]; then
  log "=== Backup finished with ${ERRORS} error(s) ==="
  exit 1
else
  log "=== Backup complete ==="
fi
