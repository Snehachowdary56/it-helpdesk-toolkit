#!/usr/bin/env bash
# Password reset or locked account: verify identity first (see docs/runbooks/password-reset.md),
# then set a temporary password that must be changed at next login and unlock the account.
# Usage: reset-password.sh <username> <ticket>
source "$(dirname "$0")/common.sh"
[ $# -eq 2 ] || { echo "Usage: $0 <username> <ticket>" >&2; exit 2; }
user=$1 ticket=$2
user_exists "$user" || { echo "No user $user" >&2; exit 3; }
uac=$(st user show "$user" --attributes=userAccountControl | awk -F': ' '/^userAccountControl/{print $2}')
if (( uac & 2 )); then echo "$user is disabled (offboarded?). Escalate: do not reset a disabled account." >&2; exit 4; fi
pw=$(temp_password)
st user setpassword "$user" --newpassword="$pw" --must-change-at-next-login >/dev/null
st user unlock "$user" >/dev/null 2>&1 || true
log_action reset-password "$user" "$ticket" "temporary password set; must change at next login; unlocked"
echo "Reset password for $user. Temporary password: $pw (user must change it at next login)"
