# Phase 2 Final Report — TeamX Private Network Service Platform

> Fill every `TODO` with YOUR OWN observed results (timestamps, outputs, screenshot names).
> Do not paste expected outputs you did not actually see. Evaluators check evidence against claims.

## 1. What changed from Phase 1

| Area | Phase 1 | Phase 2 |
|---|---|---|
| DNS | Single dnsmasq on Mac 1, records in dnsmasq.conf, TTL 60 | Primary (Mac 1) + backup (Mac 3), identical records in `teamx.hosts`, TTL 30, hot reload via SIGHUP |
| Clients | One DNS server configured | Both DNS servers configured (primary, backup) |
| Edge | nginx on Mac 2, passive failover | + retry limits, timeouts, `X-Edge` / `X-Upstream` evidence headers, upstream-aware access log |
| Standby edge | — | nginx on Mac 3 with the same certificate, used for DNS-based cutover |
| Backend access | Any LAN host could reach :3001/:3002 | pf rules: only edge machines may connect |
| Tooling | Manual commands | `watch-lb.sh`, `watch-cutover.sh`, `diagnose.sh`, `diagnose-edge.sh`, `fw.sh` |

Updated IP / service inventory:

| Machine | IP | Services (Phase 2) |
|---|---|---|
| Mac 1 | TODO | dnsmasq (primary DNS), test client |
| Mac 2 | TODO | nginx primary edge :80/:443 |
| Mac 3 | TODO | Backend A :3001, dnsmasq (backup DNS), nginx standby edge :443 |
| Mac 4 | TODO | Backend B :3002, main test client |

## 2. Resilience tests and results

For each: what we did → what we observed (with evidence file) → why.

### Extension A — Backup DNS
- Test: TODO
- Observed: TODO (evidence/phase2/A-backup-dns/...)
- Learning (one paragraph): TODO — DNS service failure vs application failure.

### Extension B — TTL and controlled record change
- Test: TODO
- Observed: TODO (time of change, time client switched, flush result)
- Learning: TODO — relate to DNS-based migration / cutover in production.

### Extension C — Service isolation
- Test: TODO
- Observed: TODO (Mac 2 → 200, client → timeout; rollback output)
- Learning: TODO — drop vs reject, defence in depth, why the edge is the only entry point.

### Extension D — HA failover
- Test: TODO
- Observed: TODO (watch-lb output showing "502, 200" retry, B-only period, A rejoining after fail_timeout)
- Learning: TODO — passive vs active health checks; nginx as single point of failure and how to remove it.

### Extension E — Edge migration (DNS cutover)
- Test: TODO
- Observed: TODO (watch-cutover output: DNS servers changed at T, client edge switched at T+≈30s)
- Learning: TODO — TTL as the cutover window; why the old edge must stay up until the TTL drains.

## 3. Troubleshooting findings (Extension F)
- Faults we practiced (fault → symptom → layer → fix): TODO
- Fault injected by faculty: TODO
- Our diagnosis path and fix: TODO

## 4. Remaining single points of failure
TODO — at minimum: the edge (Mac 2), the Wi-Fi access point / LAN itself, the CA private key, and what would remove each.

## 5. Individual contribution
| Member | Phase 2 responsibility |
|---|---|
| Tanish | TODO |
| Abhishek | TODO |
| Atharva | TODO |
| Varun | TODO |
