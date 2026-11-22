#!/bin/bash
# Point a CLIENT Mac at both team DNS servers (Extension A), or undo it.
#   sudo ./scripts/set-client-dns.sh team     -> primary Mac 1, backup Mac 3
#   sudo ./scripts/set-client-dns.sh reset    -> back to DHCP-provided DNS
#   SERVICE="USB 10/100/1000 LAN" sudo ./scripts/set-client-dns.sh team   (if not on Wi-Fi)

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/teamx.env"
SERVICE="${SERVICE:-Wi-Fi}"

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo."; exit 1; fi

case "${1:-}" in
  team)  networksetup -setdnsservers "$SERVICE" $DNS_SERVERS ;;
  reset) networksetup -setdnsservers "$SERVICE" Empty ;;
  *)     echo "Usage: sudo $0 team|reset"; exit 1 ;;
esac

dscacheutil -flushcache; killall -HUP mDNSResponder
echo "DNS servers for $SERVICE:"; networksetup -getdnsservers "$SERVICE"
echo "Resolver order the OS will use:"; scutil --dns | awk '/resolver #1/{f=1} f&&/nameserver/{print "  "$0} /resolver #2/{exit}'
