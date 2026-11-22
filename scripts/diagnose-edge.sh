#!/bin/bash
# Extension F, part 2: run ON THE EDGE (Mac 2) when the client sees 502/504 or a refused port.
#   sudo ./scripts/diagnose-edge.sh
# Checks: nginx process -> config syntax -> listening ports -> each backend directly -> recent errors.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/teamx.env"
LOGDIR="$(brew --prefix 2>/dev/null || echo /opt/homebrew)/var/log/nginx"

ok()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad() { printf '  \033[31mBAD\033[0m   %s\n' "$1"; }

echo "[1] nginx process"
if pgrep -x nginx >/dev/null; then ok "nginx is running"; else bad "nginx is NOT running -> sudo brew services start nginx"; fi

echo "[2] nginx config syntax"
if nginx -t >/dev/null 2>&1; then ok "nginx -t passes"; else bad "nginx -t FAILS:"; nginx -t 2>&1 | sed 's/^/        /'; fi

echo "[3] listening sockets (should include *:443 and *:80)"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '$1=="nginx"{print "        "$9}' | sort -u

echo "[4] upstreams configured in nginx"
nginx -T 2>/dev/null | awk '/upstream team_backends/{f=1} f&&/server /{print "        "$0} f&&/}/{exit}'

echo "[5] can the edge reach each backend directly?"
for target in "A $MAC3_BACKEND_A:$PORT_A" "B $MAC4_BACKEND_B:$PORT_B"; do
  set -- $target
  out="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$2/api/status")"; rc=$?
  if [ "$out" = "200" ]; then ok "Backend $1 ($2) answers 200"
  elif [ $rc -eq 7 ]; then bad "Backend $1 ($2) REFUSED -> process stopped, wrong port, or bound to 127.0.0.1 only"
  elif [ $rc -eq 28 ]; then bad "Backend $1 ($2) TIMEOUT -> firewall dropping the edge, or host off the LAN"
  else bad "Backend $1 ($2) -> curl exit $rc, HTTP '$out'"; fi
done

echo "[6] last nginx errors"
tail -n 8 "$LOGDIR/teamx_error.log" 2>/dev/null | sed 's/^/        /' || echo "        (no teamx_error.log yet)"
