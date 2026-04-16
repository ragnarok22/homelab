#!/bin/sh
# Homelab backup restore helper
#
# Usage:
#   ./restore.sh <backup_path> [component]
#
# Components:
#   all         Restore everything (default)
#   databases   Restore PostgreSQL databases only
#   volumes     Restore Docker volumes only
#   configs     Restore service configs only
#   env         Restore .env files only
#   list        List backup contents
#
# Examples:
#   ./restore.sh /home/Data/backups/daily/2026-04-16_030000 list
#   ./restore.sh /home/Data/backups/daily/2026-04-16_030000 databases
#   ./restore.sh /home/Data/backups/daily/2026-04-16_030000 all
#
# To restore from Google Drive (if both disks failed):
#   1. curl https://rclone.org/install.sh | sudo bash
#   2. rclone config  (set up Google Drive remote)
#   3. rclone ls gdrive:homelab-backups/daily/
#   4. rclone copy gdrive:homelab-backups/daily/LATEST /tmp/restore/
#   5. ./restore.sh /tmp/restore all

set -eu

HOMELAB_DIR="${HOMELAB_DIR:-/home/ragnarok/homelab}"

# Database users (override via env or flags if not 'postgres')
PG_USER="${PG_USER:-postgres}"
IMMICH_PG_USER="${IMMICH_PG_USER:-postgres}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <backup_path> [component]"
  echo "Components: all, databases, volumes, configs, env, list"
  exit 1
fi

BACKUP_PATH="$1"
COMPONENT="${2:-all}"

if [ ! -d "$BACKUP_PATH" ]; then
  echo "ERROR: Backup path not found: ${BACKUP_PATH}"
  exit 1
fi

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [restore] $1"
}

confirm() {
  printf "%s [y/N] " "$1"
  read -r answer
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# --- List backup contents ---
list_backup() {
  echo "=== Backup: ${BACKUP_PATH} ==="

  if [ -f "${BACKUP_PATH}/manifest.json" ]; then
    echo ""
    echo "Manifest:"
    cat "${BACKUP_PATH}/manifest.json"
  fi

  echo ""
  if [ -d "${BACKUP_PATH}/databases" ]; then
    echo "Databases:"
    ls -lh "${BACKUP_PATH}/databases/" 2>/dev/null
  fi

  echo ""
  if [ -d "${BACKUP_PATH}/volumes" ]; then
    echo "Volumes:"
    ls -lh "${BACKUP_PATH}/volumes/" 2>/dev/null
  fi

  echo ""
  if [ -d "${BACKUP_PATH}/configs" ]; then
    echo "Service configs:"
    ls -1 "${BACKUP_PATH}/configs/" 2>/dev/null
  fi

  echo ""
  if [ -d "${BACKUP_PATH}/env-files" ]; then
    echo "Env files:"
    ls -1 "${BACKUP_PATH}/env-files/" 2>/dev/null
  fi

  echo ""
  echo "Total size: $(du -sh "${BACKUP_PATH}" | cut -f1)"
}

# --- Restore databases ---
restore_databases() {
  local db_dir="${BACKUP_PATH}/databases"
  if [ ! -d "$db_dir" ]; then
    log "No database backups found"
    return
  fi

  log "Available database dumps:"
  ls -1 "$db_dir"
  echo ""

  for dump in "${db_dir}"/*.sql.gz; do
    [ -f "$dump" ] || continue
    filename=$(basename "$dump")

    # Parse container and database from filename: container_database.sql.gz
    container=$(echo "$filename" | sed 's/_[^_]*\.sql\.gz$//')
    database=$(echo "$filename" | sed "s/^${container}_//" | sed 's/\.sql\.gz$//')

    if ! confirm "Restore ${database} to ${container}?"; then
      continue
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
      log "ERROR: Container ${container} is not running. Start it first."
      continue
    fi

    # Determine the correct psql user based on container
    pg_user="${PG_USER}"
    case "$container" in
      *immich*) pg_user="${IMMICH_PG_USER}" ;;
    esac

    log "Restoring ${database} to ${container} (user: ${pg_user})..."
    if gunzip -c "$dump" | docker exec -i "${container}" psql -U "${pg_user}" -d "${database}" 2>&1; then
      log "Done: ${database}"
    else
      log "ERROR: Failed to restore ${database} to ${container}"
    fi
  done
}

# --- Restore volumes ---
restore_volumes() {
  local vol_dir="${BACKUP_PATH}/volumes"
  if [ ! -d "$vol_dir" ]; then
    log "No volume backups found"
    return
  fi

  log "Available volume backups:"
  ls -1 "$vol_dir"
  echo ""

  for archive in "${vol_dir}"/*.tar.gz; do
    [ -f "$archive" ] || continue
    vol_name=$(basename "$archive" .tar.gz)

    if ! confirm "Restore volume ${vol_name}? (This will stop services using it)"; then
      continue
    fi

    if ! docker volume inspect "${vol_name}" > /dev/null 2>&1; then
      log "Creating volume: ${vol_name}"
      docker volume create "${vol_name}"
    fi

    log "Restoring volume: ${vol_name}..."
    # Three-phase restore:
    #   1. Extract archive to /staging (fails = volume untouched)
    #   2. Move old volume content to /old (preserves rollback path)
    #   3. Copy new content; on failure, roll back from /old
    archive_name=$(basename "$archive")
    if docker run --rm \
      -v "${vol_name}:/volume" \
      -v "$(dirname "$archive"):/backup:ro" \
      alpine:3.20 sh -c '
        set -e
        # Phase 1: validate archive by extracting to staging
        mkdir -p /staging
        tar xzf /backup/'"${archive_name}"' -C /staging

        # Phase 2: move current content aside (same filesystem = fast rename)
        mkdir -p /old
        find /volume -mindepth 1 -maxdepth 1 ! -name .old_restore_bak -exec mv {} /old/ 2>/dev/null \;

        # Phase 3: copy new content
        if cp -a /staging/. /volume/; then
          rm -rf /old
        else
          echo "ROLLBACK: cp failed, restoring original content" >&2
          find /volume -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
          mv /old/* /volume/ 2>/dev/null
          rm -rf /old
          exit 1
        fi
      '; then
      log "Done: ${vol_name}"
    else
      log "ERROR: Failed to restore volume ${vol_name}"
    fi
  done
}

# --- Restore configs ---
restore_configs() {
  local cfg_dir="${BACKUP_PATH}/configs"
  if [ ! -d "$cfg_dir" ]; then
    log "No config backups found"
    return
  fi

  log "Available service configs:"
  ls -1 "$cfg_dir"
  echo ""

  for svc_dir in "${cfg_dir}"/*/; do
    [ -d "$svc_dir" ] || continue
    svc=$(basename "$svc_dir")

    if ! confirm "Restore configs for ${svc}?"; then
      continue
    fi

    dest="${HOMELAB_DIR}/${svc}"
    if [ ! -d "$dest" ]; then
      log "WARNING: Service directory ${dest} not found, creating it"
      mkdir -p "$dest"
    fi

    for archive in "${svc_dir}"*.tar.gz; do
      [ -f "$archive" ] || continue
      subdir=$(basename "$archive" .tar.gz)
      log "Restoring ${svc}/${subdir}..."
      tar xzf "$archive" -C "$dest"
    done
    log "Done: ${svc}"
  done
}

# --- Restore env files ---
restore_env_files() {
  local env_dir="${BACKUP_PATH}/env-files"
  if [ ! -d "$env_dir" ]; then
    log "No env file backups found"
    return
  fi

  log "Available .env files:"
  ls -1 "$env_dir"
  echo ""

  for envfile in "${env_dir}"/*.env; do
    [ -f "$envfile" ] || continue
    svc=$(basename "$envfile" .env)

    if ! confirm "Restore .env for ${svc}?"; then
      continue
    fi

    dest="${HOMELAB_DIR}/${svc}/.env"
    if [ -f "$dest" ]; then
      log "WARNING: ${dest} already exists, backing up to ${dest}.bak"
      cp "$dest" "${dest}.bak"
    fi

    cp "$envfile" "$dest"
    log "Done: ${svc}/.env"
  done
}

# --- Main ---
case "$COMPONENT" in
  list)
    list_backup
    ;;
  databases)
    restore_databases
    ;;
  volumes)
    restore_volumes
    ;;
  configs)
    restore_configs
    ;;
  env)
    restore_env_files
    ;;
  all)
    echo "=== Full restore from ${BACKUP_PATH} ==="
    echo ""
    echo "WARNING: This will restore databases, volumes, configs, and env files."
    echo "Make sure relevant services are stopped before proceeding."
    echo ""
    if ! confirm "Continue with full restore?"; then
      echo "Aborted."
      exit 0
    fi
    restore_databases
    restore_volumes
    restore_configs
    restore_env_files
    log "=== Full restore complete ==="
    ;;
  *)
    echo "Unknown component: ${COMPONENT}"
    echo "Valid: all, databases, volumes, configs, env, list"
    exit 1
    ;;
esac
