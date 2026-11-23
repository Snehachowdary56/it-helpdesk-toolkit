#!/usr/bin/env bash
# Shared settings for the Active Directory scripts.
#   AD_URL      where the directory is: a lab database (sam.ldb path) or ldap://dc.example.com
#   SAMBA_TOOL  the samba-tool command (default: samba-tool)
#   AD_AUTH     extra auth options for a real domain controller, e.g. "-U admin%password"
set -euo pipefail
SAMBA_TOOL=${SAMBA_TOOL:-samba-tool}
: "${AD_URL:?Set AD_URL to the directory (lab sam.ldb path or ldap://dc)}"
AD_AUTH=${AD_AUTH:-}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR=${LOG_DIR:-$ROOT/logs}
mkdir -p "$LOG_DIR"
ACTION_LOG="$LOG_DIR/ad-actions.csv"
[ -f "$ACTION_LOG" ] || echo "timestamp,action,username,ticket,detail,operator" > "$ACTION_LOG"

# samba-tool warns when a password is on the command line; the lab accepts that, a real DC should use AD_AUTH with -A <authfile>.
st() { $SAMBA_TOOL "$@" -H "$AD_URL" $AD_AUTH 2> >(grep -v "passwords on command line" >&2); }

# Base DN, e.g. DC=corp,DC=example,DC=test
base_dn() { st user show Administrator --attributes=distinguishedName | awk -F': ' '/^distinguishedName/{sub(/^CN=Administrator,CN=Users,/,"",$2); print $2}'; }

log_action() { # action username ticket detail
  printf '%s,%s,%s,%s,"%s",%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "${4//\"/\'}" "${USER:-helpdesk}" >> "$ACTION_LOG"
}

user_exists() { st user show "$1" >/dev/null 2>&1; }

ensure_ou() { # "OU=Finance,OU=Staff" (relative to base DN)
  local ou=$1 parent
  st ou list 2>/dev/null | grep -qx "$ou" && return 0
  parent=${ou#*,}
  if [ "$parent" != "$ou" ]; then ensure_ou "$parent"; fi
  st ou create "$ou" >/dev/null
}

ensure_group() { st group show "$1" >/dev/null 2>&1 || st group add "$1" --group-scope=Global --group-type=Security >/dev/null; }

temp_password() { # 16 characters with upper, lower, digit and symbol
  local p; p=$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 13)
  echo "${p}#7a"
}

valid_username() { [[ $1 =~ ^[a-z][a-z0-9.]{1,19}$ ]]; }
