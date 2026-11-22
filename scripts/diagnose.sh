#!/bin/bash
# Extension F: layer-by-layer fault diagnosis from a CLIENT Mac.
#   ./scripts/diagnose.sh                 (checks https://app.teamX.test/api/status)
#   ./scripts/diagnose.sh api.teamX.test
#
# Order = the order a request actually happens in, so the FIRST failure is the broken layer:
#   1 resolver config -> 2 DNS -> 3 IP reachability -> 4 TCP -> 5 TLS -> 6 HTTP/application
# Read each line out loud during the evaluation — the method earns marks even before the fix.

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/teamx.env"
HOST="${1:-$DOMAIN}"
PORT="$HTTPS_PORT"
if [ "$PORT" = "443" ]; then URL="https://$HOST/api/status"; else URL="https://$HOST:$PORT/api/status"; fi

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; printf '\n\033[1mVERDICT: fault is at the %s layer.\033[0m\n%s\n' "$2" "$3"; exit 1; }
hdr()  { printf '\n\033[1m[%s] %s\033[0m\n' "$1" "$2"; }

echo "Diagnosing $URL   ($(date '+%H:%M:%S'))"

# ---------------------------------------------------------------- 1. resolver config
hdr 1 "Which DNS servers is this client using?"
servers="$(scutil --dns 2>/dev/null | awk '/resolver #1/{f=1} f&&/nameserver\[/{print $3} /resolver #2/{exit}' | tr '\n' ' ')"
echo "  OS resolver #1 nameservers: ${servers:-none}"
team_listed=0
for s in $DNS_SERVERS; do case " $servers " in *" $s "*) team_listed=1;; esac; done
if [ "$team_listed" -eq 1 ]; then pass "client points at a team DNS server"
else warn "no team DNS server ($DNS_SERVERS) in the client's resolver list — check Network settings"; fi

# ---------------------------------------------------------------- 2. DNS
hdr 2 "DNS: does $HOST resolve, and to the right IP?"
alive=0
for s in $DNS_SERVERS; do
  ans="$(dig +short +time=2 +tries=1 @"$s" "$HOST" 2>&1 | head -1)"
  case "$ans" in
    ""|*NXDOMAIN*)            echo "  @$s -> (no record / NXDOMAIN)";;
    *"timed out"*|*refused*|*"communications error"*|*";;"*) echo "  @$s -> DNS service NOT answering";;
    *)                        echo "  @$s -> $ans"; alive=1;;
  esac
done
ip="$(dscacheutil -q host -a name "$HOST" 2>/dev/null | awk '/^ip_address:/{print $2; exit}')"
echo "  OS resolver (with cache)  -> ${ip:-nothing}"
if [ -z "$ip" ]; then
  if [ "$alive" -eq 0 ]; then
    fail "no team DNS server answers for $HOST" "DNS" \
         "Both DNS services are down/unreachable or the record is missing. Check: dnsmasq running (sudo brew services list), records in teamx.hosts, 'dig @<server> $HOST'."
  else
    fail "DNS servers answer but this client cannot resolve $HOST" "DNS (client resolver config)" \
         "The client is not using the team DNS servers. Fix: sudo ./scripts/set-client-dns.sh team"
  fi
fi
case "$ip" in
  "$MAC2_EDGE_PRIMARY") pass "$HOST -> $ip (primary edge, Mac 2)";;
  "$MAC3_BACKEND_A")    pass "$HOST -> $ip (standby edge, Mac 3 — OK only if a cutover is in progress)";;
  *) warn "$HOST -> $ip, which is NOT an edge machine. Wrong DNS record? (DNS succeeded but points to the wrong place.) Continuing with $ip.";;
esac

# ---------------------------------------------------------------- 3. IP reachability
hdr 3 "IP: is $ip reachable?"
if ping -c 2 -t 3 "$ip" >/dev/null 2>&1; then pass "ping $ip OK"
else warn "ping $ip failed (host down, off the Wi-Fi, or ICMP filtered). Continuing to TCP test."; fi

# ---------------------------------------------------------------- 4. TCP
hdr 4 "TCP: does $ip accept a connection on port $PORT?"
nc_out="$(nc -vz -G 3 "$ip" "$PORT" 2>&1)"
case "$nc_out" in
  *succeeded*|*open*|*Connected*) pass "TCP handshake to $ip:$PORT completed";;
  *refused*) fail "$ip:$PORT -> connection REFUSED (host replied with RST)" "TCP / transport" \
             "The machine is up but nothing listens on $PORT: nginx stopped, nginx on a different port, or wrong port in the URL. On the edge: sudo lsof -nP -iTCP:$PORT -sTCP:LISTEN";;
  *) fail "$ip:$PORT -> TIMEOUT (no SYN-ACK)" "TCP / network path" \
          "Packets are dropped: firewall (pf) blocking $PORT, host off the LAN, or wrong IP. Output: $nc_out";;
esac

# ---------------------------------------------------------------- 5. TLS
hdr 5 "TLS: handshake + certificate valid for $HOST?"
cert="$(echo | openssl s_client -connect "$ip:$PORT" -servername "$HOST" 2>/dev/null | openssl x509 2>/dev/null)"
if [ -z "$cert" ]; then
  fail "no certificate received — TLS handshake failed" "TLS" \
       "Something answers on $PORT but does not speak TLS (e.g. 'listen 443' without 'ssl', or plain HTTP on that port). Check the listen line in nginx."
fi
echo "$cert" | openssl x509 -noout -subject -issuer -enddate 2>/dev/null | sed 's/^/  /'
echo "$cert" | openssl x509 -noout -text 2>/dev/null | awk '/Subject Alternative Name/{getline; gsub(/^ +/,""); print "  SAN: "$0}'
if ! echo "$cert" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
  fail "certificate has EXPIRED" "TLS" "Re-issue server.crt (cn-certs/make-certs.sh) and reload nginx."
fi
curl -s -o /dev/null --max-time 5 "$URL"; rc=$?
case "$rc" in
  0) pass "curl validated the certificate chain and hostname (no -k used)";;
  60|51) fail "certificate NOT trusted for $HOST (curl exit $rc)" "TLS (certificate trust)" \
              "Either the SAN does not contain $HOST, the cert was not signed by our local CA, or rootCA.pem is missing from this Mac's Keychain (System, 'Always Trust').";;
  35) fail "TLS handshake error (curl exit 35)" "TLS" "Protocol/cipher mismatch or broken ssl_* config on the edge. Check nginx error log.";;
  28) fail "timed out after TCP connected (curl exit 28)" "application (edge stuck)" "nginx accepted TCP but never answered. Check nginx error log on the edge.";;
  *)  echo "  curl exit code $rc (not a TLS error) — moving on to HTTP.";;
esac

# ---------------------------------------------------------------- 6. HTTP / application
hdr 6 "HTTP: what does the application return?"
resp="$(curl -s -o /dev/null -D - --max-time 8 "$URL" | tr -d '\r')"
code="$(echo "$resp" | awk 'NR==1{print $2}')"
echo "$resp" | grep -iE '^(HTTP|x-backend|x-edge|x-upstream|x-upstream-status|server|cache-control):' | sed 's/^/  /'
case "$code" in
  200) pass "HTTP 200 — full path DNS -> TCP -> TLS -> nginx -> backend works";
       echo; echo "VERDICT: no fault visible from this client. If one backend should be serving and isn't, run scripts/watch-lb.sh"; exit 0;;
  502) fail "HTTP 502 Bad Gateway from the edge" "application / upstream (edge -> backend)" \
            "DNS, TCP, TLS and nginx are fine. nginx could not connect to ANY backend: both stopped, wrong upstream IP/port in nginx, backend bound to 127.0.0.1, or pf blocking the edge. Run scripts/diagnose-edge.sh on Mac 2.";;
  504) fail "HTTP 504 Gateway Timeout" "application / upstream" "nginx reached a backend but it did not reply in time (or connect timed out on both). Run scripts/diagnose-edge.sh on Mac 2.";;
  404) fail "HTTP 404" "application" "Request reached a server but the path/route does not exist — wrong proxy_pass, wrong server block (server_name), or the app route changed.";;
  "") fail "no HTTP response" "application" "TLS worked but no HTTP response came back. Check nginx error log.";;
  *) fail "unexpected HTTP $code" "application" "Read the headers above and the nginx error log.";;
esac
