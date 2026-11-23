# Runbook: routine server checks (weekly)

1. **Linux:** `linux/health-check.sh --services "ssh cron <app service>"`
   **Windows:** `powershell -ExecutionPolicy Bypass -File windows\health-check.ps1`
2. Read every WARN and CRIT line:
   - Service not running: restart it once, check its log (`journalctl -u <service> -n 50` or Event Viewer). If it stops again, escalate.
   - Disk over 80%: find large folders (`du -sh /var/* | sort -h`) and old logs; never delete application data without approval.
   - Pending updates or reboot: schedule them in the maintenance window and tell users first.
   - Many errors in the logs: note the top sources and escalate if they are new.
3. Monthly: run `ad/audit.sh` and fix or report every finding (directory hygiene).
4. Record the results in the maintenance ticket.
