# Runbook: tickets, documentation and escalation

## Every ticket records
- Who, what, when, and the exact error message or screenshot
- Steps already tried (by the user and by you)
- What fixed it, or why it was escalated
- Time spent

## Priority
| Priority | Example | Response |
|---|---|---|
| P1 | A system is down for many people | Phone the on-call senior engineer now |
| P2 | One person cannot work at all | Within 1 hour |
| P3 | Something is slow or one feature fails | Same day |
| P4 | Request (new software, equipment) | Within 3 working days |

## Escalate with diagnostics
Before escalating a server problem, run `linux/health-check.sh --collect /tmp/diag` (Linux)
or `windows\health-check.ps1 -ReportPath C:\Temp\health.json` (Windows) and attach the output to the ticket.
Escalate when: a runbook step fails, the fix needs admin rights you do not have, data could be lost,
or a security issue is suspected (phishing, unknown logins). For security issues, do not investigate alone.
