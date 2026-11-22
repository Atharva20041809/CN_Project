# Phase 2 bundle — what goes where

Copy this folder's contents over the repo root (same folder names), commit, then each person pulls.

| File | Runs on | Purpose |
|---|---|---|
| `dns/dnsmasq-phase2.conf` | Mac 1 + Mac 3 | dnsmasq config (TTL 30, records from teamx.hosts) → `/opt/homebrew/etc/dnsmasq.conf` |
| `dns/teamx.hosts` | Mac 1 + Mac 3 | The records. Must be identical on both → `/opt/homebrew/etc/teamx.hosts` |
| `nginx/nginx.conf` | Mac 2 (+ Mac 3) | Clean main config — removes the leftover plain-HTTP block → `/opt/homebrew/etc/nginx/nginx.conf` |
| `nginx/teamX.conf` | — | The REAL Phase 1 edge config (from your `nginx -T`), new IPs — replaces the wrong HTTP-only file in the repo |
| `dns/dnsmasq.conf` | — | Phase 1 DNS config, new IP (kept for the record) |
| `nginx/teamX-phase2.conf` | Mac 2 | Primary edge → `/opt/homebrew/etc/nginx/servers/teamX.conf` (check cert paths!) |
| `nginx/teamX-standby.conf` | Mac 3 | Standby edge for Extension E |
| `firewall/pf-backend-a.conf` | Mac 3 | pf rules: only edges may reach :3001 |
| `firewall/pf-backend-b.conf` | Mac 4 | pf rules: only edges may reach :3002 |
| `firewall/fw.sh` | Mac 3, Mac 4 | apply / status / allow / rollback the pf rules |
| `scripts/update-ips.sh` | repo | When IPs change: `./scripts/update-ips.sh <mac1> <mac2> <mac3> <mac4>` rewrites every file |
| `scripts/teamx.env` | all | IPs used by every script — edit here if IPs change |
| `scripts/set-client-dns.sh` | client Macs | point client at primary + backup DNS |
| `scripts/watch-lb.sh` | client | live load-balancing / failover view (Extension D) |
| `scripts/watch-cutover.sh` | client | live DNS cache vs server view (Extensions B + E) |
| `scripts/diagnose.sh` | client | layer-by-layer fault finder (Extension F) |
| `scripts/diagnose-edge.sh` | Mac 2 | edge-side checks when client sees 502/504 |
| `cn-certs/make-certs.sh` | — | FIXED: old script failed (`req_ext` section did not exist) |
| `cn-backend/cn-backend-b/server.js` | Mac 4 | FIXED: defaults were "A"/3001 |
| `docs/PHASE2_REPORT.md` | — | Final report template |
| `evidence/phase2/*` | — | Empty folders for Phase 2 screenshots |

After copying: `chmod +x scripts/*.sh firewall/fw.sh cn-certs/make-certs.sh`
