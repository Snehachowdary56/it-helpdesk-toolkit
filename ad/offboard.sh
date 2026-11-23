#!/usr/bin/env bash
# Leaver: disable the account, remove it from every group (keeps Domain Users),
# move it to the Disabled Users OU, and record the date and ticket in the action log.
# Usage: offboard.sh <username> <ticket>
source "$(dirname "$0")/common.sh"
[ $# -eq 2 ] || { echo "Usage: $0 <username> <ticket>" >&2; exit 2; }
user=$1 ticket=$2
user_exists "$user" || { echo "No user $user" >&2; exit 3; }
removed=()
while read -r g; do
  [ -z "$g" ] || [ "$g" = "Domain Users" ] && continue
  st group removemembers "$g" "$user" >/dev/null && removed+=("$g")
done < <(st user getgroups "$user")
st user disable "$user" >/dev/null
ensure_ou "OU=Disabled Users"
st user move "$user" "OU=Disabled Users" >/dev/null
log_action offboard "$user" "$ticket" "disabled; removed from ${removed[*]:-no groups}; moved to Disabled Users"
echo "Disabled $user, removed from ${#removed[@]} group(s) (${removed[*]:-none}), moved to OU=Disabled Users"
