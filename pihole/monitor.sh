#!/usr/bin/env bash
# Pi-hole health monitor
#
# Checks DNS resolution and auto-restarts the container if unhealthy.
# Collects system diagnostics before restarting to help find root cause.
#
# Install as cron job (every 5 minutes):
#   */5 * * * * /path/to/pihole/monitor.sh

set -euo pipefail

LOGFILE="/var/log/pihole-monitor.log"
CONTAINER="pihole"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE"
}

# Test DNS resolution via Pi-hole
# Check both local and upstream resolution — Pi-hole can resolve local
# records (pi.hole) even when upstream forwarding is broken.
if dig +short +retry=0 +time=3 @127.0.0.1 google.com > /dev/null 2>&1; then
  exit 0
fi

log "ALERT: Pi-hole DNS check failed (upstream resolution) — collecting diagnostics"

# Collect diagnostics BEFORE restarting to capture the degraded state
{
  echo "--- DIAGNOSTICS $(date) ---"
  echo "=== UPTIME / LOAD ==="
  uptime
  echo "=== CONNTRACK ==="
  cat /proc/sys/net/netfilter/nf_conntrack_count
  cat /proc/sys/net/netfilter/nf_conntrack_max
  echo "=== SOCKETS ==="
  ss -s
  echo "=== FILE DESCRIPTORS ==="
  cat /proc/sys/fs/file-nr
  echo "=== MEMORY ==="
  free -h
  echo "=== DEFAULT ROUTES ==="
  ip route show default
  echo "=== ROUTE TO 8.8.8.8 ==="
  ip route get 8.8.8.8
  echo "=== PIHOLE CONTAINER ==="
  docker inspect "$CONTAINER" --format 'Status={{.State.Status}} Health={{.State.Health.Status}} Pid={{.State.Pid}} Started={{.State.StartedAt}}'
  echo "=== PIHOLE LOGS (last 20 lines) ==="
  docker logs "$CONTAINER" --tail 20 2>&1
  echo "--- END DIAGNOSTICS ---"
} >> "$LOGFILE" 2>&1

# Attempt container restart
log "ACTION: Restarting $CONTAINER container"
docker restart "$CONTAINER" >> "$LOGFILE" 2>&1

# Wait for container to be ready
sleep 30

# Verify DNS works after restart
if dig +short +retry=0 +time=5 @127.0.0.1 google.com > /dev/null 2>&1; then
  log "RESOLVED: Container restart fixed DNS"
else
  log "UNRESOLVED: DNS still failing after container restart — server reboot likely needed"
fi
