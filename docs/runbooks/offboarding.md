# Runbook: offboarding (employee leaving)

**Trigger:** offboarding ticket from HR or the manager, with the last day.
**Do it** at the end of the last working day (or immediately for an urgent termination).

1. Run `ad/offboard.sh <username> <ticket>`: disables the account, removes it from all groups and moves it to `OU=Disabled Users`.
2. Collect equipment: `python inventory/inventory.py user <username>` lists everything assigned. Return each item:
   `python inventory/inventory.py return <tag> --ticket <ticket> --condition good|damaged`
3. Ask the manager where the person's files and mailbox should go; escalate mailbox moves to a senior engineer.
4. Never delete the account on the same day. The monthly audit (`ad/audit.sh`) lists disabled accounts for review.
5. Note in the ticket: time disabled, groups removed, equipment returned, anything still missing.
