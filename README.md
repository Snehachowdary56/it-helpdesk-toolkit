# IT Help Desk Toolkit

![CI](https://github.com/Snehachowdary56/it-helpdesk-toolkit/actions/workflows/ci.yml/badge.svg)

Scripts and runbooks for day-to-day IT support: **Active Directory** account management (onboarding,
offboarding, password resets, directory hygiene audits), **Linux and Windows server health checks**,
**IT equipment inventory**, and **runbooks** for the help desk. Everything is tested in CI against a real
Active Directory domain (Samba AD, which speaks the same protocols as Windows Server AD) and on a Windows runner.

| Folder | What it does |
|---|---|
| `ad/onboard.sh` | New hire: creates the account in the department OU (`OU=Finance,OU=Staff`), adds the department's security groups from `config/department-groups.csv`, sets a temporary password that must be changed at first login |
| `ad/offboard.sh` | Leaver: disables the account, removes it from every group, moves it to `OU=Disabled Users` |
| `ad/reset-password.sh` | Password reset or locked account: temporary password (must change at next login) and unlock; refuses disabled accounts |
| `ad/audit.sh` | Directory hygiene audit to CSV: disabled accounts still in groups, accounts outside `OU=Staff`, never-used accounts, passwords that never expire, empty groups |
| `linux/health-check.sh` | Services, disk, memory, errors in the logs, pending updates, reboot needed; exit 0/1/2 for OK/WARN/CRITICAL; `--collect` makes a diagnostic bundle to attach when escalating |
| `windows/health-check.ps1` | Stopped automatic services, disk space, System and Application event log errors, uptime, pending reboot; JSON report |
| `inventory/inventory.py` | Laptops, monitors and peripherals: add, assign, return, who has what, warranty ending, laptops in stock for new hires |
| `docs/runbooks/` | Onboarding (accounts + hardware setup), offboarding, password reset and access issues, tickets and escalation, routine server maintenance |

Every AD action is written to `logs/ad-actions.csv` (time, action, user, ticket, operator) for audits.

## Tests

- **13 pytest tests** (CI on Ubuntu): a test domain `CORP.EXAMPLE.TEST` is created with Samba AD; the tests onboard,
  reset, offboard and audit real accounts and check OUs, groups, `pwdLastSet` (must change password) and
  `userAccountControl` (disabled); Linux health check exit codes and diagnostic bundle; inventory rules and CLI.
- **Windows job**: runs `health-check.ps1` on a Windows runner and checks the JSON report.
- **ShellCheck** on every Bash script.

## Try it on Linux (Ubuntu)

```bash
sudo apt install samba samba-ad-dc
sudo samba-tool domain provision --realm=CORP.EXAMPLE.TEST --domain=CORP --server-role=dc \
  --dns-backend=NONE --adminpass='Adm1n!Passw0rd#2026' --targetdir=$HOME/adlab
export AD_URL=$HOME/adlab/private/sam.ldb SAMBA_TOOL="sudo samba-tool"
ad/onboard.sh asha.k Asha Kumar Finance HD-101 "Accountant"
ad/reset-password.sh asha.k HD-102
ad/offboard.sh asha.k HD-103
ad/audit.sh
linux/health-check.sh --services "ssh cron"
python3 inventory/inventory.py add LT-0001 laptop "Dell Latitude 5440" --warranty 2028-03-31
```

Against a real domain controller set `AD_URL=ldap://dc01.corp.example.com` and `AD_AUTH="-U helpdesk"`.

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File windows\health-check.ps1 -ReportPath C:\Temp\health.json
```

## Notes
- The lab domain and all names are made up.
- Temporary passwords are shown once and must be given by phone or in person; the runbook requires identity checks first.
