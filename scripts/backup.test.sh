#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/homelab"

cat > "${tmp_dir}/bin/flock" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "-n" ]; then
  exit "${FLOCK_STATUS:-0}"
fi
exec "$@"
STUB
chmod +x "${tmp_dir}/bin/flock"

cat > "${tmp_dir}/bin/timeout" <<'STUB'
#!/bin/bash
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --kill-after=*) shift ;;
    --preserve-status) shift ;;
    *) shift ;;
  esac
done

duration="${1:-0}"
shift
seconds="${duration%s}"

"$@" &
pid=$!
(
  sleep "$seconds"
  kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$pid" 2>/dev/null || true
) &
watcher=$!

set +e
wait "$pid"
status=$?
set -e
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true

if [ "$status" -gt 128 ]; then
  exit 124
fi
exit "$status"
STUB
chmod +x "${tmp_dir}/bin/timeout"

cat > "${tmp_dir}/bin/docker" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${DOCKER_CALLS_FILE}"

case "$*" in
  "exec immich_postgres "*)
    sleep 10
    exit 0
    ;;
  "exec postgres "*)
    printf '%s\n' 'select 1;'
    exit 0
    ;;
  "exec invoice-ninja-db "*)
    printf '%s\n' 'create table ok(id int);'
    exit 0
    ;;
  "volume inspect "*)
    exit 1
    ;;
esac

exit 0
STUB
chmod +x "${tmp_dir}/bin/docker"

export PATH="${tmp_dir}/bin:${PATH}"
export DOCKER_CALLS_FILE="${tmp_dir}/docker.calls"

set +e
BACKUP_ROOT="${tmp_dir}/backups" \
BACKUP_STAGING_ROOT="${tmp_dir}/staging" \
BACKUP_LOCK_FILE="${tmp_dir}/backup.lock" \
BACKUP_COMMAND_TIMEOUT_SECONDS=1 \
BACKUP_ARCHIVE_TIMEOUT_SECONDS=1 \
BACKUP_MAX_SECONDS=30 \
BACKUP_KILL_AFTER_SECONDS=1 \
HOMELAB_DIR="${tmp_dir}/homelab" \
ALERTS_ENV="${tmp_dir}/missing-alerts.env" \
"$BACKUP_SCRIPT" > "${tmp_dir}/output" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "expected backup to fail when immich pg_dump hangs"
  cat "${tmp_dir}/output"
  exit 1
fi

if ! grep -q "ERROR: pg_dump failed for immich_postgres/immich" "${tmp_dir}/output"; then
  echo "expected hung pg_dump to be reported as a failed dump"
  cat "${tmp_dir}/output"
  exit 1
fi

if find "${tmp_dir}/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
  echo "expected failed backup to avoid publishing a final backup directory"
  find "${tmp_dir}/backups" -mindepth 1 -maxdepth 2 -print
  exit 1
fi

if find "${tmp_dir}/staging" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q .; then
  echo "expected failed backup staging directory to be cleaned up"
  find "${tmp_dir}/staging" -mindepth 1 -maxdepth 2 -print
  exit 1
fi

set +e
FLOCK_STATUS=1 \
BACKUP_ROOT="${tmp_dir}/lock-backups" \
BACKUP_STAGING_ROOT="${tmp_dir}/lock-staging" \
BACKUP_LOCK_FILE="${tmp_dir}/backup.lock" \
BACKUP_MAX_SECONDS=30 \
BACKUP_KILL_AFTER_SECONDS=1 \
HOMELAB_DIR="${tmp_dir}/homelab" \
ALERTS_ENV="${tmp_dir}/missing-alerts.env" \
"$BACKUP_SCRIPT" > "${tmp_dir}/lock-output" 2>&1
lock_status=$?
set -e

if [ "$lock_status" -eq 0 ]; then
  echo "expected backup to fail when lock is already held"
  cat "${tmp_dir}/lock-output"
  exit 1
fi

if ! grep -q "another backup is already running" "${tmp_dir}/lock-output"; then
  echo "expected lock failure to be reported"
  cat "${tmp_dir}/lock-output"
  exit 1
fi

echo "backup timeout and lock tests passed"
