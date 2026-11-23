# Runbook: new hire onboarding

**Trigger:** onboarding ticket from HR with name, department, start date, manager and job title.
**Time:** about 45 minutes, done the day before the start date.

## 1. Account (Active Directory)
1. Check the ticket has the department and manager. If not, ask HR before creating anything.
2. Run: `ad/onboard.sh <first.last> <First> <Last> <Department> <ticket> "<Job title>"`
   - Creates the user in `OU=<Department>,OU=Staff`, adds the department's security groups
     (from `config/department-groups.csv`) and sets a temporary password that must be changed at first login.
3. Extra access (shared drives, applications) needs the manager's approval in the ticket. Never copy another user's groups.

## 2. Hardware setup
1. Pick a laptop in stock: `python inventory/inventory.py report` shows how many are free.
2. Image or update it, install standard software, sign in once to check it joins the network.
3. Set up the dock, monitor, keyboard, mouse and headset at the desk; test both monitors and the camera.
4. Record each item: `python inventory/inventory.py assign <tag> <username> --ticket <ticket>`

## 3. First morning
1. Give the temporary password in person or by phone, never by email.
2. Walk the user through changing it, setting up multi-factor authentication and the VPN.
3. Update the ticket with what was done and close it.
