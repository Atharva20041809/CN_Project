#!/bin/bash
# Extension D: live view of load balancing + failover, one request per second.
#   ./scripts/watch-lb.sh            (Ctrl+C to stop)
#   ./scripts/watch-lb.sh /api/cached
#
# Each line: time | HTTP status | backend that answered | edge | upstream(s) nginx tried
# Two upstreams on one line ("A, B") = nginx hit a dead backend and retried on the other.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/teamx.env"
PATH_PART="${1:-/api/status}"
if [ "$HTTPS_PORT" = "443" ]; then URL="https://$DOMAIN$PATH_PART"; else URL="https://$DOMAIN:$HTTPS_PORT$PATH_PART"; fi

echo "Watching $URL"
printf '%-9s %-6s %-8s %-14s %s\n' TIME STATUS BACKEND EDGE "UPSTREAM(S) TRIED"
while true; do
  hdrs="$(curl -s -o /dev/null -D - --max-time 4 "$URL" | tr -d '\r')"
  if [ -z "$hdrs" ]; then
    printf '%-9s %s\n' "$(date +%H:%M:%S)" "NO RESPONSE (curl failed — DNS/TCP/TLS problem?)"
  else
    echo "$hdrs" | awk -v t="$(date +%H:%M:%S)" '
      NR==1              { status=$2 }
      tolower($1)=="x-backend:"  { $1=""; backend=substr($0,2) }
      tolower($1)=="x-edge:"     { $1=""; edge=substr($0,2) }
      tolower($1)=="x-upstream:" { $1=""; up=substr($0,2) }
      END { printf "%-9s %-6s %-8s %-14s %s\n", t, status, (backend?backend:"-"), (edge?edge:"-"), (up?up:"-") }'
  fi
  sleep 1
done
