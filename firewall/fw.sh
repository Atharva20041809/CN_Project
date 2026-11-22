#!/bin/bash
# Extension C helper — run on the BACKEND Macs only (Mac 3 = A, Mac 4 = B).
#
#   sudo ./fw.sh apply A|B        back up current pf state, load rules, enable pf
#   sudo ./fw.sh status           show pf state, our rules, and the allow-list
#   sudo ./fw.sh allow <ip>       add a machine to the allow-list   (e.g. standby edge)
#   sudo ./fw.sh disallow <ip>    remove a machine from the allow-list
#   sudo ./fw.sh rollback         remove our rules, release pf, show we're back to original
#
# Written for macOS's built-in bash 3.2.

set -u
ANCHOR="com.apple/teamx"
STATE_DIR="/var/tmp/teamx-pf"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo."; exit 1; fi
mkdir -p "$STATE_DIR"

case "${1:-}" in
  apply)
    which="$(echo "${2:-}" | tr '[:upper:]' '[:lower:]')"
    rules="$DIR/pf-backend-$which.conf"
    if [ ! -f "$rules" ]; then echo "Usage: sudo $0 apply A|B"; exit 1; fi

    # Rollback copy: original pf.conf, the full active ruleset and pf status BEFORE we touch anything
    cp /etc/pf.conf "$STATE_DIR/pf.conf.backup"
    pfctl -sr 2>/dev/null          > "$STATE_DIR/rules-before.txt"
    pfctl -s info 2>/dev/null | head -1 > "$STATE_DIR/status-before.txt"
    echo "Backup saved in $STATE_DIR (pf.conf.backup, rules-before.txt, status-before.txt)"

    pfctl -nf "$rules" -a "$ANCHOR" || { echo "Syntax check failed — nothing changed."; exit 1; }
    pfctl -a "$ANCHOR" -f "$rules" 2>/dev/null

    # Enable pf with a reference token, so rollback releases only OUR hold on pf
    token="$(pfctl -E 2>&1 | awk '/Token/{print $NF}')"
    echo "$token" > "$STATE_DIR/token"
    echo "pf enabled (token $token). Active teamx rules:"
    pfctl -a "$ANCHOR" -sr 2>/dev/null
    ;;

  status)
    pfctl -s info 2>/dev/null | head -1
    echo "--- rules in anchor $ANCHOR ---"
    pfctl -a "$ANCHOR" -sr 2>/dev/null
    echo "--- allow-list <edges> ---"
    pfctl -a "$ANCHOR" -t edges -T show 2>/dev/null
    ;;

  allow)
    [ -n "${2:-}" ] || { echo "Usage: sudo $0 allow <ip>"; exit 1; }
    pfctl -a "$ANCHOR" -t edges -T add "$2"
    pfctl -a "$ANCHOR" -t edges -T show 2>/dev/null
    ;;

  disallow)
    [ -n "${2:-}" ] || { echo "Usage: sudo $0 disallow <ip>"; exit 1; }
    pfctl -a "$ANCHOR" -t edges -T delete "$2"
    pfctl -a "$ANCHOR" -t edges -T show 2>/dev/null
    ;;

  rollback)
    pfctl -a "$ANCHOR" -F all 2>/dev/null          # flush our rules + table
    if [ -s "$STATE_DIR/token" ]; then
      pfctl -X "$(cat "$STATE_DIR/token")" 2>/dev/null   # release our pf enable reference
      rm -f "$STATE_DIR/token"
    fi
    if [ -f "$STATE_DIR/pf.conf.backup" ] && ! cmp -s /etc/pf.conf "$STATE_DIR/pf.conf.backup"; then
      cp "$STATE_DIR/pf.conf.backup" /etc/pf.conf && pfctl -f /etc/pf.conf 2>/dev/null
      echo "/etc/pf.conf restored from backup."
    fi
    echo "Rolled back. Current status:"
    pfctl -s info 2>/dev/null | head -1
    pfctl -sr 2>/dev/null > "$STATE_DIR/rules-after.txt"
    if diff -q "$STATE_DIR/rules-before.txt" "$STATE_DIR/rules-after.txt" >/dev/null 2>&1; then
      echo "Active ruleset identical to before 'apply'."
    else
      echo "Ruleset differs from before — compare:"
      diff "$STATE_DIR/rules-before.txt" "$STATE_DIR/rules-after.txt"
    fi
    ;;

  *)
    sed -n '2,10p' "$0"; exit 1 ;;
esac
