#!/usr/bin/env bash
# Routine Linux server check: services, disk, memory, recent errors in the logs, pending updates, uptime.
# Prints a report and exits 0 (OK), 1 (WARN) or 2 (CRITICAL) so monitoring or cron can alert on it.
# Usage: health-check.sh [--services "ssh cron nginx"] [--collect DIR]
#   --collect DIR  also saves a diagnostic bundle (tar.gz) to attach when escalating to senior engineers
set -uo pipefail
SERVICES=${SERVICES:-"ssh cron"}
DISK_WARN=${DISK_WARN:-80}; DISK_CRIT=${DISK_CRIT:-90}
COLLECT=""
while [ $# -gt 0 ]; do
  case $1 in
    --services) SERVICES=$2; shift 2;;
    --collect) COLLECT=$2; shift 2;;
    *) echo "Unknown option $1" >&2; exit 64;;
  esac
done
status=0; lines=()
flag() { # level message
  lines+=("[$1] $2")
  if [ "$1" = CRIT ]; then status=2; elif [ "$1" = WARN ] && (( status < 1 )); then status=1; fi
  return 0
}

# Services: systemd if present, otherwise look for the process
for svc in $SERVICES; do
  if command -v systemctl >/dev/null && systemctl list-unit-files "$svc.service" >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    if systemctl is-active --quiet "$svc"; then flag OK "service $svc is running"
    else flag CRIT "service $svc is not running (try: sudo systemctl restart $svc; then check: journalctl -u $svc -n 50)"; fi
  elif pgrep -x "$svc" >/dev/null || pgrep -x "${svc}d" >/dev/null; then
    flag OK "process $svc is running"
  else
    flag WARN "service $svc not found or not running"
  fi
done

# Disk usage per mounted filesystem
while read -r use mount; do
  pct=${use%\%}
  if (( pct >= DISK_CRIT )); then flag CRIT "disk $mount is ${pct}% full"
  elif (( pct >= DISK_WARN )); then flag WARN "disk $mount is ${pct}% full"
  else flag OK "disk $mount is ${pct}% full"; fi
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR>1 {print $5, $6}')

# Memory
mem_pct=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo)
if (( mem_pct >= 90 )); then flag WARN "memory ${mem_pct}% used"; else flag OK "memory ${mem_pct}% used"; fi

# Errors in the logs during the last 24 hours
if command -v journalctl >/dev/null && [ -d /run/systemd/system ]; then
  errs=$(journalctl -p err --since "24 hours ago" --no-pager -q 2>/dev/null | wc -l)
elif [ -r /var/log/syslog ]; then
  errs=$(grep -ciE "error|fail" /var/log/syslog || true)
else
  errs=0
fi
if (( errs > 50 )); then flag WARN "$errs error lines in the logs in 24h (journalctl -p err --since '24 hours ago')"
else flag OK "$errs error lines in the logs in 24h"; fi

# Pending updates (Debian/Ubuntu)
if command -v apt >/dev/null; then
  upd=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
  if (( upd > 0 )); then flag WARN "$upd package update(s) pending (sudo apt upgrade in the maintenance window)"; else flag OK "no pending updates"; fi
fi
if [ -f /var/run/reboot-required ]; then flag WARN "reboot required after updates"; fi

up=$(awk '{printf "%d days", $1/86400}' /proc/uptime)
echo "Health check: $(hostname) at $(date -u +%Y-%m-%dT%H:%M:%SZ), up $up"
printf '%s\n' "${lines[@]}"
echo "Overall: $( [ $status -eq 0 ] && echo OK || ([ $status -eq 1 ] && echo WARN || echo CRITICAL) )"

if [ -n "$COLLECT" ]; then
  d=$(mktemp -d); mkdir -p "$COLLECT"
  { printf '%s\n' "${lines[@]}"; } > "$d/health.txt"
  uname -a > "$d/uname.txt"; df -h > "$d/disk.txt" 2>&1; free -m > "$d/memory.txt" 2>&1
  ps aux --sort=-%cpu 2>/dev/null | head -20 > "$d/top-processes.txt"
  (journalctl -p warning --since "24 hours ago" --no-pager -q 2>/dev/null || tail -n 500 /var/log/syslog 2>/dev/null) > "$d/recent-logs.txt"
  bundle="$COLLECT/diagnostics-$(hostname)-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
  tar -czf "$bundle" -C "$d" . && rm -rf "$d"
  echo "Diagnostic bundle for escalation: $bundle"
fi
exit $status
