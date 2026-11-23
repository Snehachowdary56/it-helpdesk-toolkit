#!/usr/bin/env bash
# New hire: create the account in the department OU, add the department's security groups,
# and set a temporary password that must be changed at first login.
# Usage: onboard.sh <username> <first> <last> <department> <ticket> [job title]
source "$(dirname "$0")/common.sh"
[ $# -ge 5 ] || { echo "Usage: $0 <username> <first> <last> <department> <ticket> [job title]" >&2; exit 2; }
user=$1 first=$2 last=$3 dept=$4 ticket=$5 title=${6:-}
valid_username "$user" || { echo "Invalid username '$user' (lowercase letters, digits, dots; 2-20 chars)" >&2; exit 2; }
groups=$(awk -F, -v d="$dept" 'NR>1 && $1==d {print $2}' "$ROOT/config/department-groups.csv")
[ -n "$groups" ] || { echo "Unknown department '$dept'. Add it to config/department-groups.csv first." >&2; exit 2; }
if user_exists "$user"; then echo "User $user already exists: not changed." >&2; exit 3; fi

ou="OU=$dept,OU=Staff"
ensure_ou "$ou"
pw=$(temp_password)
st user create "$user" "$pw" --given-name="$first" --surname="$last" --userou="$ou" \
  --department="$dept" ${title:+--job-title="$title"} --must-change-at-next-login >/dev/null
for g in ${groups//;/ }; do ensure_group "$g"; st group addmembers "$g" "$user" >/dev/null; done
log_action onboard "$user" "$ticket" "OU=$dept; groups=$groups"
echo "Created $user ($first $last) in $ou; groups: ${groups//;/, }"
echo "Temporary password (give it to the user in person or by phone, never by email): $pw"
