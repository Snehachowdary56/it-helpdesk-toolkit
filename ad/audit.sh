#!/usr/bin/env bash
# Directory hygiene audit. Writes a CSV of findings and prints a summary.
#   disabled-in-groups   disabled account still in security groups (should have been removed)
#   outside-staff-ou     enabled person account not in OU=Staff (hard to manage with policies)
#   never-logged-in      enabled account created more than STALE_DAYS ago that has never logged in
#   password-never-expires
#   empty-group          security group (GG-*) with no members
# Usage: audit.sh [report.csv]
source "$(dirname "$0")/common.sh"
out=${1:-$LOG_DIR/ad-audit.csv}
STALE_DAYS=${STALE_DAYS:-30}
SYSTEM_ACCOUNTS="Administrator Guest krbtgt"
now=$(date -u +%s)
echo "finding,object,detail" > "$out"
add() { echo "$1,$2,\"$3\"" >> "$out"; }

while read -r u; do
  [ -z "$u" ] && continue
  case " $SYSTEM_ACCOUNTS " in *" $u "*) continue;; esac
  [[ $u == dns-* ]] && continue
  info=$(st user show "$u" --attributes=distinguishedName,userAccountControl,whenCreated,lastLogonTimestamp)
  dn=$(awk -F': ' '/^distinguishedName/{print $2}' <<<"$info")
  uac=$(awk -F': ' '/^userAccountControl/{print $2}' <<<"$info")
  created=$(awk -F': ' '/^whenCreated/{print $2}' <<<"$info")
  lastlogon=$(awk -F': ' '/^lastLogonTimestamp/{print $2}' <<<"$info")
  groups=$(st user getgroups "$u" | grep -v '^Domain Users$' | paste -sd';' - || true)
  if (( uac & 2 )); then
    [ -n "$groups" ] && add disabled-in-groups "$u" "still in: $groups"
    continue
  fi
  [[ $dn == *",OU=Staff,"* ]] || add outside-staff-ou "$u" "$dn"
  (( uac & 65536 )) && add password-never-expires "$u" "userAccountControl=$uac"
  if [ -z "$lastlogon" ] && [ -n "$created" ]; then
    created_s=$(date -u -d "${created:0:4}-${created:4:2}-${created:6:2} ${created:8:2}:${created:10:2}:${created:12:2}" +%s)
    age=$(( (now - created_s) / 86400 ))
    (( age >= STALE_DAYS )) && add never-logged-in "$u" "created $age days ago, never logged in"
  fi
done < <(st user list)

while read -r g; do
  [[ $g == GG-* ]] || continue
  [ -z "$(st group listmembers "$g")" ] && add empty-group "$g" "no members"
done < <(st group list)

total=$(( $(wc -l < "$out") - 1 ))
echo "Audit complete: $total finding(s) written to $out"
tail -n +2 "$out" | cut -d, -f1 | sort | uniq -c | sed 's/^/  /'
