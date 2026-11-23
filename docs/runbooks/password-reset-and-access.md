# Runbook: password reset, locked account and access issues

## Verify identity first
Never reset a password just because someone asks. Confirm at least two of: employee ID, manager's name,
a callback to the phone number in the directory, or an in-person check with a badge.

## Password reset or locked out
1. Run `ad/reset-password.sh <username> <ticket>`: sets a temporary password that must be changed at next login and unlocks the account.
2. If it says the account is **disabled**, stop and escalate: the person may have left.
3. Give the temporary password by phone or in person. Ask the user to sign in and change it while you wait.
4. If the account keeps locking, collect the time of each lockout and the devices the user signs in on
   (an old phone with a saved password is the usual cause) and escalate with that information.

## "I can't open a folder or application"
1. Ask for the exact path or application and the error message (screenshot).
2. Check the user's groups: `samba-tool user getgroups <username>` (or Active Directory Users and Computers).
3. Access is only added with the owner's or manager's approval in the ticket. Add them to the right security group, not directly to the folder.
4. Ask the user to sign out and back in (group changes apply at sign-in).
