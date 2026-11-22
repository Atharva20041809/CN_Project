#!/bin/bash
# Extensions B + E: watch a DNS change propagate, every 2 seconds. Run on a CLIENT Mac.
#   ./scripts/watch-cutover.sh                  (watch app.teamX.test — Extension E)
#   ./scripts/watch-cutover.sh ttl.teamX.test   (watch the TTL demo record — Extension B)
#
# Columns:
#   OS_CACHE    what THIS Mac's resolver (mDNSResponder, with its cache) returns — what curl/browsers use
#   MAC1 / MAC3 what each DNS server answers right now (dig asks them directly, bypassing the OS cache)
#   EDGE        which edge actually served the HTTPS request (X-Edge header)
#
# During a cutover you will see MAC1/MAC3 change immediately while OS_CACHE and EDGE stay on the
# old edge until the 30s TTL runs out. Flush to force it:
#   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/teamx.env"
NAME="${1:-$DOMAIN}"
if [ "$HTTPS_PORT" = "443" ]; then URL="https://$DOMAIN/api/status"; else URL="https://$DOMAIN:$HTTPS_PORT/api/status"; fi

echo "Watching $NAME"
printf '%-9s %-15s %-15s %-15s %s\n' TIME OS_CACHE MAC1_DNS MAC3_DNS EDGE
while true; do
  t="$(date +%H:%M:%S)"
  os="$(dscacheutil -q host -a name "$NAME" 2>/dev/null | awk '/^ip_address:/{print $2; exit}')"
  d1="$(dig +short +time=1 +tries=1 @"$MAC1_DNS_PRIMARY" "$NAME" 2>/dev/null | head -1)"
  d3="$(dig +short +time=1 +tries=1 @"$MAC3_BACKEND_A" "$NAME" 2>/dev/null | head -1)"
  edge="-"
  [ "$NAME" = "$DOMAIN" ] && edge="$(curl -s -o /dev/null -D - --max-time 3 "$URL" | tr -d '\r' | awk 'tolower($1)=="x-edge:"{print $2}')"
  case "$d1" in ""|*";;"*) d1="down";; esac
  case "$d3" in ""|*";;"*) d3="down";; esac
  printf '%-9s %-15s %-15s %-15s %s\n' "$t" "${os:--}" "$d1" "$d3" "${edge:-no-response}"
  sleep 2
done
