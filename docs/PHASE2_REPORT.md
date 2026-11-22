# Phase 2 Final Report — TeamX Private Network Service Platform

**Team:** Tanish (Mac 1) · Abhishek Rana (Mac 2) · Atharva Tiwari (Mac 3) · Varun Sharma (Mac 4)
**Tests run:** 22 Nov 2026, 21:00–00:15 IST, campus Wi-Fi (10.7.0.0/19)
**Evidence:** `evidence/phase2/` (A–E) and `evidence/failures/`

---

## 1. What changed from Phase 1

| Area | Phase 1 | Phase 2 |
|---|---|---|
| DNS | One dnsmasq server (Mac 1); records in `dnsmasq.conf`; TTL 60 | Primary (Mac 1) **and backup (Mac 3)** with identical records in `dns/teamx.hosts`; TTL **30**; record changes applied with `SIGHUP` (no restart) |
| Clients | One DNS server configured | Both DNS servers configured (primary 10.7.23.138, backup 10.7.3.174) |
| Edge (Mac 2) | nginx, TLS, round-robin, passive failover | + retry limits and timeouts, `X-Edge` / `X-Upstream` / `X-Upstream-Status` evidence headers, upstream-aware access log; leftover plain-HTTP block removed from `nginx.conf` |
| Standby edge | — | nginx on Mac 3 with the same certificate, used for DNS-based cutover |
| Backend access | Any LAN host could reach :3001 / :3002 | pf rules (loaded on demand): only the edge may connect |
| Tooling | Manual commands | `scripts/diagnose.sh`, `diagnose-edge.sh`, `watch-lb.sh`, `watch-cutover.sh`, `update-ips.sh`, `firewall/fw.sh` |
| Fixes | — | `cn-certs/make-certs.sh` (wrong extension section), Backend B defaults (were "A"/3001), committed nginx config now matches the running one |

### IP and service inventory (22 Nov 2026)

| Machine | Owner | IP | Services |
|---|---|---|---|
| Mac 1 | Tanish | 10.7.23.138 | dnsmasq — primary DNS; test client |
| Mac 2 | Abhishek | 10.7.3.38 | nginx — primary edge, :80 → :443, TLS termination, load balancer |
| Mac 3 | Atharva | 10.7.3.174 | Backend A :3001 · dnsmasq — backup DNS · nginx — standby edge :443 |
| Mac 4 | Varun | 10.7.31.162 | Backend B :3002 · main test client |

---

## 2. Resilience tests and results

### Extension A — Backup DNS resolver

**Test.** Mac 4 was configured with both DNS servers. We stopped dnsmasq on Mac 1 (`brew services stop dnsmasq`), resolved `app.teamX.test` from Mac 4, made an HTTPS request, then restarted Mac 1.

**Observed** (dnsmasq logs on Mac 1 and Mac 3, plus Mac 4 terminal):

| Time | Event |
|---|---|
| 21:53:45 | Mac 1 log: `exiting on receipt of SIGTERM` — primary down |
| 21:54:14 | Mac 4 `dig`: answer `10.7.3.38`, **`SERVER: 10.7.3.174`**, query time 78 ms. Mac 3 log records the same query from 10.7.31.162 |
| 21:54:14 | Mac 4 `curl https://app.teamX.test/api/status` → `HTTP/2 200`, `x-edge: mac2-primary` |
| 21:54:46 | Mac 1 dnsmasq restarted |
| 21:55:04 | Mac 4 `dig` → `SERVER: 10.7.23.138` again |

Evidence: `A1`–`A5` in `evidence/phase2/A-backup-dns/`.

**Learning.** Name resolution continued with no visible error because both servers hold identical records. Failover took only 78 ms because Mac 1 was still up: with nothing listening on UDP/53 it replied immediately with ICMP "port unreachable", and the resolver moved straight to the backup. Had Mac 1 been powered off, the client would have waited for a timeout first. A DNS failure is different from an application failure. In a DNS failure the name cannot be resolved even though the edge and backends are healthy. In an application failure DNS answers correctly but the TCP, TLS or HTTP step fails. Failover also only happens when the primary does not respond: an NXDOMAIN from the primary is a valid answer and would not be retried on the backup, which is why the two servers must hold the same records.

### Extension B — DNS TTL and controlled record change

**Test.** `dig` showed a TTL of 30 s on `app.teamX.test` and on the test record `ttl.teamX.test`. With `watch-cutover.sh ttl.teamX.test` running on Mac 4, we changed `ttl.teamX.test` from 10.7.3.38 to 10.7.31.162 on both DNS servers (`sed` + `killall -HUP dnsmasq`). We then changed it back and flushed Mac 4's cache manually.

**Observed.** Both DNS servers returned the new address immediately. Mac 4's OS resolver cache (`OS_CACHE` column, which reflects what curl and browsers use) kept returning the old address until the cached entry's 30 s TTL expired, then switched. On the reverse change, `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` made the client switch on the next lookup with no wait.

Evidence: `B1` (TTL 30), `B2` (cache lagging behind the servers), `B3` (immediate change after the flush) in `evidence/phase2/B-dns-ttl/`.

**Learning.** `dig @server` asks the authoritative server directly and always sees the current record. Applications go through the OS cache and see the old answer for up to one TTL. In production this is the cutover window for DNS-based migration. Teams lower the TTL well before the change, switch the record, keep the old target running for at least one old-TTL so cached clients still succeed, then raise the TTL again. A low TTL means faster moves but more DNS queries.

### Extension C — Service isolation (pf firewall)

**Test.** Before: Mac 1 could reach both backends directly. We loaded pf rules on Mac 3 (port 3001) and Mac 4 (port 3002) with `firewall/fw.sh apply`. The rules sit in the anchor `com.apple/teamx`, so `/etc/pf.conf` is never edited. The rules allow loopback, allow the edge (table `<edges>` = 10.7.3.38) and silently drop everyone else. `fw.sh` saved a rollback copy of `pf.conf`, the full ruleset and the pf status before applying.

**Observed.**

| From | Test | Result |
|---|---|---|
| Mac 2 (edge) | `curl` Backend A and B directly | JSON from both — allowed |
| Mac 1 (client) | `nc -vz -G 5` to :3001 and :3002 | Timed out — blocked |
| Mac 4 (client) | `nc -vz -G 5 10.7.3.174 3001` | Timed out — blocked |
| Mac 4 | `watch-lb.sh` through `https://app.teamX.test` | A/B alternating, HTTP 200 — service unaffected |
| After rollback | `fw.sh rollback` on Mac 3 and Mac 4; Mac 1 `curl` | `Active ruleset identical to before 'apply'`; Mac 1 could reach both backends again |

**Finding during rollback.** On Mac 3, releasing the pf enable-token left pf in the `Enabled` state, although it had been `Disabled` before the test. The active ruleset was already identical, so nothing was blocked. To restore the original configuration exactly, we disabled pf with `sudo pfctl -d` and verified `Status: Disabled` on both backend Macs (`C7b`).

Evidence: `C1`–`C9`, `C7b` in `evidence/phase2/C-service-isolation/`.

**Learning.** The backends no longer need to be reachable by clients at all. nginx is the only legitimate caller, as with a cloud security group that admits traffic only from the load balancer's group. We used **drop** rather than reject. A dropped SYN produces a timeout, which reveals nothing to a scanner, whereas a stopped service answers with a TCP RST ("connection refused"). The difference between the two is itself a diagnostic signal. pf (the packet filter) is a separate layer from the macOS Application Firewall.

### Extension D — High-availability failover

**Test.** With `watch-lb.sh` on Mac 4 (one HTTPS request per second) and the nginx access log open on Mac 2, we stopped Backend A, restarted it, then stopped both backends and restarted them.

**Observed.**
- **A stopped:** one request shows two upstreams tried (`10.7.3.174:3001, 10.7.31.162:3002`, upstream status `502, 200`). nginx's attempt to A failed, the same request was retried on B, and the client received 200. All following requests went to B only.
- **A restarted:** after the 10 s `fail_timeout`, nginx sent A a real request again; it succeeded and A/B alternation resumed.
- **Both stopped:** HTTP 502 Bad Gateway, with both upstreams listed as tried (`502, 502`). DNS, TCP and TLS to the edge still succeeded, which shows exactly where the edge ends and the backends begin.

Evidence: `D1`–`D6` in `evidence/phase2/D-ha-failover/` (`D2` and `D5` show the retry).

**Learning.** Open-source nginx performs **passive** health checks. A backend is marked down after `max_fails=1` real request fails, and retried after `fail_timeout=10s`. `proxy_next_upstream error timeout http_502 http_503 http_504` with `proxy_next_upstream_tries 2` hides a single backend failure from users. Active probing (`health_check`) needs nginx Plus or another load balancer. Non-idempotent requests such as POST are not retried by default, because the first backend may already have acted on them.

**Single point of failure.** The edge nginx on Mac 2 remains a SPOF. If Mac 2 fails, DNS still returns 10.7.3.38 and every client fails. Other SPOFs are the Wi-Fi access point and the CA private key. Ways to remove the edge SPOF:
- a floating virtual IP shared by two edges (VRRP/keepalived), taken over in about a second with no DNS change
- health-checked DNS failover (for example Route 53 failover records), bounded by TTL
- a managed or anycast load balancer run redundantly by the provider

Extension E is a manual version of the DNS approach.

### Extension E — Controlled edge migration (DNS cutover)

**Test.** We built a standby nginx on Mac 3 with the same configuration and certificate; its upstreams are Backend A via loopback and Backend B. Before cutting over, Mac 4 tested it directly:
`curl --resolve app.teamX.test:443:10.7.3.174 https://app.teamX.test/api/status` → `HTTP/2 200`, `x-edge: mac3-standby`, `x-upstream: 127.0.0.1:3001`, with no certificate error. With `watch-cutover.sh` running on Mac 4, we changed `app.teamX.test` from 10.7.3.38 to 10.7.3.174 on both DNS servers, keeping Mac 2 running. We then rolled back the same way.

**Observed.** Both DNS servers answered 10.7.3.174 immediately. Mac 4's cached answer and the serving edge stayed on Mac 2 (`mac2-primary`) until the 30 s TTL expired, then switched to `mac3-standby` with no failed requests. The rollback behaved the same in reverse.

Evidence: `E1` (standby tested), `E2` (cutover), `E3` (rollback) in `evidence/phase2/E-edge-cutover/`.

**Learning.** The same certificate works on another machine because TLS validates the **hostname** against the certificate's SAN, not the IP address. That is also why the private key was copied only by AirDrop and never committed. The TTL defines how long cached clients keep using the old edge, so the old edge must stay up until that window has drained. Existing keep-alive connections do not re-resolve at all. DNS cutover suits planned migrations; for sudden failures a floating IP is faster.

---

## 3. Troubleshooting findings

These are real faults we hit while building Phase 2, each diagnosed layer by layer (resolver → DNS → IP → TCP → TLS → HTTP → upstream).

| # | Symptom | Diagnosis (layer) | Fix |
|---|---|---|---|
| 1 | Whole service down at the start of Phase 2 | **IP layer.** DHCP had given Mac 1, 2 and 4 new addresses, but DNS still pointed `app.teamX.test` at Mac 2's old IP and nginx still sent Backend B traffic to Mac 4's old IP | Rewrote every IP with `scripts/update-ips.sh`, reinstalled the configs |
| 2 | `nginx -s reload` → `kill(…) failed: No such process` | **Service.** The config was valid (`nginx -t` OK) but nginx was not running; the PID file was stale | `sudo brew services start nginx`; confirmed `*:443 (LISTEN)` with `lsof` |
| 3 | After restarting dnsmasq, Mac 4's queries to Mac 1 timed out; Mac 1's own `dig` worked | Ping OK (**IP fine**), DNS timed out (**DNS service / UDP 53 filtered**). Same /19 subnet, so not a routing issue. The macOS Application Firewall on these university-**managed** Macs blocked the restarted dnsmasq binary until allowed; it cannot be changed from the CLI | Allowed via the system prompt; from then on records are changed with `killall -HUP dnsmasq` (no restart) |
| 4 | `http://10.7.3.38` served backend content over plain HTTP | **Application/config.** A leftover `server { listen 80; }` block in the main `nginx.conf` proxied straight to the backends, bypassing TLS | Replaced `nginx.conf` with a clean version that only includes `servers/*.conf` |
| 5 | `make-certs.sh` failed: `Error checking extension section req_ext` | **TLS tooling.** The script referenced a section that `leaf.cnf` names `v3_leaf` | Fixed to `-extensions v3_leaf` (and `-extensions v3_ca` for the CA) |
| 6 | Risk: Backend B started without env vars identifies as "A" on 3001 | **Application.** Wrong defaults in `server.js` | Defaults changed to `B` / `3002` |
| 7 | pf `Enabled` after rollback | **Firewall state.** Token release did not return pf to Disabled | `sudo pfctl -d`; verified `Disabled` |

### Phase 1 failure demonstrations completed in Phase 2

- **DNS record points to the wrong IP** (`evidence/failures/dns-wrong-ip-failure.png`). The record was changed to 10.7.31.162. `dig` returned 10.7.31.162 and `ping` succeeded, but `curl` failed with "Couldn't connect to server" on port 443. DNS is a directory: it answered correctly but sent the client to a host that does not run the service.
- **Wrong destination port** (`evidence/failures/wrong-port-failure.png`). `nc` to 10.7.3.38:8443 gave `Connection refused`, while 10.7.3.38:443 `succeeded`. Same host, different port: IP addresses identify machines, ports identify services.
- **Both backends stopped → 502** and **one backend stopped → service continues**: see Extension D (`D4`, `D2`).

### Extension F — faculty-injected fault

*To be completed after the evaluation: the fault injected, the layer identified, our diagnosis path and the fix.*

Method we will follow (also implemented in `scripts/diagnose.sh` and `scripts/diagnose-edge.sh`):
1. resolver config
2. DNS answer
3. IP reachability
4. TCP connection to :443 (refused vs timeout)
5. TLS handshake and certificate trust
6. HTTP status
7. on the edge: `nginx -t`, listening sockets, direct curl to each backend, error log

---

## 4. Individual contribution

| Member | Phase 2 responsibility |
|---|---|
| Tanish (Mac 1) | Primary DNS migration to Phase 2 config (TTL 30, hosts-file records), record changes for Extensions B/E, failover demo |
| Abhishek Rana (Mac 2) | Phase 2 nginx config, clean `nginx.conf`, failover/retry configuration, access-log evidence |
| Atharva Tiwari (Mac 3) | Backend A, backup DNS, standby edge, pf rules for :3001 |
| Varun Sharma (Mac 4) | Backend B, client configuration, all client-side tests and evidence, pf rules for :3002 |
