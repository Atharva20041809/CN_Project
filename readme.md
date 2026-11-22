# Private Network Service Platform — TeamX

A private-network web service built on **four physical macOS laptops on the same LAN**, with no cloud.
A client resolves `app.teamX.test` through the team's own DNS, connects over HTTPS to an nginx edge, and is served by one of two backends.
Phase 1 builds and observes the system. Phase 2 hardens it: backup DNS, TTL-controlled record changes, backend isolation, HA failover and DNS-based edge migration.

## Team

| Machine | Student | Enrollment | Phase 1 role | Phase 2 additions |
| --- | --- | --- | --- | --- |
| Mac 1 | Tanish Roa | 2401010474 | Primary DNS (dnsmasq) | Test client |
| Mac 2 | Abhishek Rana | 2401010021 | nginx edge — TLS, reverse proxy, load balancer | Failover tuning, evidence headers |
| Mac 3 | Atharva Tiwari | 2401010113 | Backend A :3001 | **Backup DNS** + **standby edge** |
| Mac 4 | Varun Sharma | 2401010497 | Backend B :3002 | Main test client |

## IP and service inventory

Campus Wi-Fi, subnet 10.7.0.0/19. These addresses are DHCP leases; if they change, run `./scripts/update-ips.sh <mac1> <mac2> <mac3> <mac4>` (see "If IPs change").

| Machine | IP | Service | Port |
| --- | --- | --- | --- |
| Mac 1 | 10.7.23.138 | dnsmasq (primary DNS) | 53/udp |
| Mac 2 | 10.7.3.38 | nginx (primary edge) | 80 → 443/tcp |
| Mac 3 | 10.7.3.174 | Backend A (Node/Express) · dnsmasq (backup DNS) · nginx (standby edge) | 3001 · 53/udp · 443/tcp |
| Mac 4 | 10.7.31.162 | Backend B (Node/Express) | 3002 |

## Topology (Phase 2)

```text
                          Private LAN  10.7.0.0/19
   ┌───────────────────────────┬──────────────────────────────┬───────────────────────────┐
   │                           │                              │                           │
 Mac 1  10.7.23.138          Mac 2  10.7.3.38              Mac 3  10.7.3.174            Mac 4  10.7.31.162
 dnsmasq  PRIMARY DNS        nginx  PRIMARY EDGE :443       Backend A :3001              Backend B :3002
 test client                 TLS termination                dnsmasq  BACKUP DNS          main test client
                             round-robin + failover         nginx  STANDBY EDGE :443
                                   │                              ▲                           ▲
                                   ├──────── HTTP :3001 ──────────┘                           │
                                   └──────── HTTP :3002 ──────────────────────────────────────┘

   pf (Ext C): Backend A/B ports accept connections only from the edge.
```

## Request flow

```text
Client (Mac 4)
  │ 1. DNS query  app.teamX.test        → Mac 1 (primary)  or  Mac 3 (backup)   [UDP 53, TTL 30]
  │    answer 10.7.3.38 (Mac 2)
  │ 2. TCP handshake                    → Mac 2 :443
  │ 3. TLS handshake, cert CN/SAN app.teamX.test, signed by "teamX Local Root CA"
  │ 4. HTTP/2 GET /api/status (encrypted)
  ▼
Mac 2 nginx ── round-robin, passive health checks, retry on error ──┬─► Mac 3 Backend A :3001
                                                                     └─► Mac 4 Backend B :3002
Response carries:  X-Backend (which backend)  ·  X-Edge (which edge)  ·  X-Upstream (backends tried)
```

## Endpoints (both backends)

| Endpoint | Response |
| --- | --- |
| `GET /` | Service info JSON |
| `GET /api/status` | `{"backend":"A","status":"ok",...}`, `Cache-Control: no-store` |
| `GET /api/cached` | `Cache-Control: public, max-age=60` + `ETag`; matching `If-None-Match` → `304 Not Modified` |

Every response carries `X-Backend: A` or `X-Backend: B`.

## Repository layout

```text
CN_Project/
├── readme.md
├── PHASE2_FILES.md              where every Phase 2 file is installed
├── architecture/                topology + request-flow diagrams
├── cn-backend/
│   ├── cn-backend-a/            Backend A (Mac 3)
│   └── cn-backend-b/            Backend B (Mac 4)
├── cn-certs/                    ca.cnf, leaf.cnf, make-certs.sh, server.crt  (keys never committed)
├── dns/
│   ├── dnsmasq.conf             Phase 1 config
│   ├── dnsmasq-phase2.conf      Phase 2 config — Mac 1 AND Mac 3
│   └── teamx.hosts              the records — identical on Mac 1 and Mac 3
├── nginx/
│   ├── nginx.conf               clean main config
│   ├── teamX.conf               Phase 1 edge config
│   ├── teamX-phase2.conf        Phase 2 primary edge (Mac 2)
│   └── teamX-standby.conf       standby edge (Mac 3)
├── firewall/
│   ├── pf-backend-a.conf        Mac 3: only the edge may reach :3001
│   ├── pf-backend-b.conf        Mac 4: only the edge may reach :3002
│   └── fw.sh                    apply / status / allow / disallow / rollback
├── scripts/
│   ├── teamx.env                shared IPs
│   ├── update-ips.sh            rewrite every IP when DHCP changes them
│   ├── set-client-dns.sh        point a client at primary + backup DNS
│   ├── diagnose.sh              layer-by-layer fault finder (client)
│   ├── diagnose-edge.sh         edge-side checks (Mac 2)
│   ├── watch-lb.sh              live load-balancing / failover view
│   └── watch-cutover.sh         live DNS cache vs server view
├── docs/
│   ├── SETUP.md · RUNBOOK.md
│   └── PHASE2_REPORT.md         Phase 2 final report
└── evidence/
    ├── lan/ dns/ backends/ loadbalancer/ tls/ caching/ wireshark/ failures/   Phase 1
    └── phase2/  A-backup-dns/ B-dns-ttl/ C-service-isolation/ D-ha-failover/ E-edge-cutover/ F-troubleshooting/
```

## Starting the system

Run every command from the repo root (Mac 3's clone is `~/cn-project`).

| Order | Mac | Command |
| --- | --- | --- |
| 1 | Mac 1 | `sudo brew services start dnsmasq` |
| 2 | Mac 3 | `sudo brew services start dnsmasq` (backup DNS) |
| 3 | Mac 3 | `cd cn-backend/cn-backend-a && npm install && BACKEND=A PORT=3001 node server.js` |
| 4 | Mac 4 | `cd cn-backend/cn-backend-b && npm install && BACKEND=B PORT=3002 node server.js` |
| 5 | Mac 2 | `sudo nginx -t && sudo brew services start nginx` |
| 6 | Mac 3 | `sudo brew services start nginx` (standby edge, only needed for Extension E) |
| 7 | Client | `sudo ./scripts/set-client-dns.sh team` |
| 8 | Client | `./scripts/diagnose.sh` → must end with `HTTP 200` |

Installing the configs for the first time is described in `PHASE2_FILES.md`.

## Verification

```bash
dig app.teamX.test                 # 10.7.3.38, TTL 30, SERVER = 10.7.23.138
curl -i https://app.teamX.test/api/status    # HTTP/2 200, x-backend, x-edge: mac2-primary (no -k)
./scripts/watch-lb.sh              # A and B alternating
curl -I https://app.teamX.test/api/cached    # Cache-Control + ETag; If-None-Match → 304
```

## Phase 2 extensions

| Ext | What | How to demonstrate | Evidence |
| --- | --- | --- | --- |
| A | Backup DNS on Mac 3 | Stop dnsmasq on Mac 1 → client `dig` shows `SERVER: 10.7.3.174`, HTTPS still 200 | `evidence/phase2/A-backup-dns/` |
| B | TTL 30 + record change | `./scripts/watch-cutover.sh ttl.teamX.test`, change the record on both DNS servers + `sudo killall -HUP dnsmasq`; cache lags ≤30 s; flush = instant | `evidence/phase2/B-dns-ttl/` |
| C | Backend isolation | `sudo ./firewall/fw.sh apply A` (Mac 3) / `apply B` (Mac 4); Mac 2 allowed, clients time out; `fw.sh rollback` | `evidence/phase2/C-service-isolation/` |
| D | HA failover | `./scripts/watch-lb.sh`, stop Backend A → retry line + B only → A rejoins after 10 s; both down → 502 | `evidence/phase2/D-ha-failover/` |
| E | DNS-based edge migration | `./scripts/watch-cutover.sh`, point `app` at 10.7.3.174 on both DNS servers → edge switches to `mac3-standby` after the TTL | `evidence/phase2/E-edge-cutover/` |
| F | Fault diagnosis | `./scripts/diagnose.sh` (client) and `sudo ./scripts/diagnose-edge.sh` (Mac 2), layer by layer | `evidence/phase2/F-troubleshooting/` |

Full results and learnings: `docs/PHASE2_REPORT.md`.

## Changing a DNS record (both servers, no restart)

```bash
sudo nano /opt/homebrew/etc/teamx.hosts      # on Mac 1 AND Mac 3 — keep them identical
sudo killall -HUP dnsmasq                    # reload records; avoids the managed-Mac firewall re-prompt a restart triggers
```

## If IPs change

```bash
./scripts/update-ips.sh <mac1> <mac2> <mac3> <mac4>    # rewrites teamx.env, teamx.hosts, nginx and pf configs
git commit -am "Update IPs" && git push
```

Then, on each Mac after `git pull`, run the reinstall commands the script prints.

## Security and repository policy

- Private keys (`*.key`, `rootCA.key`) are never committed. The server key reached the standby edge only by AirDrop.
- `.gitignore` excludes keys, CSRs, `.env` files and `node_modules`.
- `X-Upstream` headers expose backend IPs for demonstration only; remove them in a real deployment.
