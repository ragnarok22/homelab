#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_DISK="${SCRIPT_DIR}/check-disk.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "${tmp_dir}/bin"

cat > "${tmp_dir}/bin/df" <<'STUB'
#!/bin/bash
human=false
if [ "${1:-}" = "-P" ]; then
  shift
elif [ "${1:-}" = "-h" ]; then
  human=true
  shift
fi

path="${1:-}"
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
case "$path" in
  /)
    if [ "$human" = true ]; then
      echo "/dev/root 118G 118G 0 100% /"
    else
      echo "/dev/root 123456 123456 0 100% /"
    fi
    ;;
  /home/Data)
    if [ "$human" = true ]; then
      echo "/dev/sda1 1.8T 1.1T 665G 62% /home/Data"
    else
      echo "/dev/sda1 123456 76543 46913 62% /home/Data"
    fi
    ;;
  *)
    exit 1
    ;;
esac
STUB
chmod +x "${tmp_dir}/bin/df"

cat > "${tmp_dir}/bin/curl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "${tmp_dir}/curl.calls"
STUB
chmod +x "${tmp_dir}/bin/curl"

cat > "${tmp_dir}/alerts.env" <<ENV
NTFY_URL=http://ntfy.local
NTFY_TOPIC=homelab-alerts
DISK_ALERT_THRESHOLD=90
DISK_ALERT_STATE_FILE=${tmp_dir}/state
ENV

set +e
PATH="${tmp_dir}/bin:${PATH}" ALERTS_ENV="${tmp_dir}/alerts.env" "$CHECK_DISK" > "${tmp_dir}/output" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "expected check-disk.sh to fail when root filesystem is full"
  cat "${tmp_dir}/output"
  exit 1
fi

if ! grep -q "Disk usage high" "${tmp_dir}/curl.calls" 2>/dev/null; then
  echo "expected an ntfy alert when root filesystem is full"
  cat "${tmp_dir}/output"
  exit 1
fi

set +e
PATH="${tmp_dir}/bin:${PATH}" ALERTS_ENV="${tmp_dir}/alerts.env" "$CHECK_DISK" /home/Data > "${tmp_dir}/output-explicit" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "expected explicit /home/Data check to ignore full root filesystem"
  cat "${tmp_dir}/output-explicit"
  exit 1
fi

set +e
PATH="${tmp_dir}/bin:${PATH}" ALERTS_ENV="${tmp_dir}/alerts.env" DISK_CHECK_PATHS="/home/Data" "$CHECK_DISK" > "${tmp_dir}/output-env" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "expected DISK_CHECK_PATHS override to check only /home/Data"
  cat "${tmp_dir}/output-env"
  exit 1
fi

echo "check-disk root-full alert test passed"
