#!/bin/bash
# Rewrite every project IP in the repo in one go, when the Wi-Fi hands out new addresses.
#
#   ./scripts/update-ips.sh <mac1> <mac2> <mac3> <mac4>
#   e.g. ./scripts/update-ips.sh 10.7.23.138 10.7.3.38 10.7.3.174 10.7.31.162
#
# Run from anywhere inside the repo. Old IPs are read from scripts/teamx.env.
# Rewrites: scripts/teamx.env, dns/teamx.hosts, nginx/*.conf, firewall/*.conf, readme.md, docs/*.md,
#           dns/readme.md, nginx/readme.md, cn-backend/readme.md
# Then prints what each Mac must re-install. (macOS bash 3.2 + perl, both built in.)

set -e
if [ $# -ne 4 ]; then sed -n '2,10p' "$0"; exit 1; fi
for ip in "$@"; do
  echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || { echo "Not an IPv4 address: $ip"; exit 1; }
done

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
. "$DIR/teamx.env"

OLD1="$MAC1_DNS_PRIMARY"; OLD2="$MAC2_EDGE_PRIMARY"; OLD3="$MAC3_BACKEND_A"; OLD4="$MAC4_BACKEND_B"
NEW1="$1"; NEW2="$2"; NEW3="$3"; NEW4="$4"

echo "Mac 1  $OLD1 -> $NEW1"
echo "Mac 2  $OLD2 -> $NEW2"
echo "Mac 3  $OLD3 -> $NEW3"
echo "Mac 4  $OLD4 -> $NEW4"

cd "$ROOT"
FILES=""
for f in scripts/teamx.env dns/teamx.hosts nginx/*.conf firewall/*.conf readme.md README.md \
         docs/*.md dns/readme.md nginx/readme.md cn-backend/readme.md; do
  [ -f "$f" ] && FILES="$FILES $f"
done

# One pass with a lookup table, matching whole IPs only — so swapped addresses can't collide
# and 10.7.3.38 never touches 10.7.3.174.
export O1="$OLD1" O2="$OLD2" O3="$OLD3" O4="$OLD4" N1="$NEW1" N2="$NEW2" N3="$NEW3" N4="$NEW4"
# shellcheck disable=SC2086
perl -pi -e '
  BEGIN { %m = ($ENV{O1}=>$ENV{N1}, $ENV{O2}=>$ENV{N2}, $ENV{O3}=>$ENV{N3}, $ENV{O4}=>$ENV{N4}); }
  s/(?<![\d.])(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?!\.?\d)/exists $m{$1} ? $m{$1} : $1/ge;
' $FILES

echo
echo "Updated:$FILES"
echo
cat <<EOF
Now re-install on each Mac (after git pull):
  Mac 1 + Mac 3 (DNS):  sudo cp dns/teamx.hosts /opt/homebrew/etc/teamx.hosts && sudo killall -HUP dnsmasq
  Mac 2 (edge):         sudo cp nginx/teamX-phase2.conf /opt/homebrew/etc/nginx/servers/teamX.conf && sudo nginx -t && sudo nginx -s reload
  Mac 3 (standby edge): sudo cp nginx/teamX-standby.conf /opt/homebrew/etc/nginx/servers/teamX.conf && sudo nginx -t && sudo nginx -s reload
  Mac 3 / Mac 4 (pf):   sudo ./firewall/fw.sh rollback   (re-apply later with the new rules if needed)
  Clients:              sudo ./scripts/set-client-dns.sh team
Then from Mac 4:        ./scripts/diagnose.sh
EOF
