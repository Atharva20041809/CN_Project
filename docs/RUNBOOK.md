# Private Network Service Platform — Runbook

This runbook provides the commands and procedures required to start, verify, diagnose, and recover the Private Network Service Platform.

## 1. Network Overview

| Machine | Role                          | IP Address    | Service       |
| ------- | ----------------------------- | ------------- | ------------- |
| Mac 1   | Private DNS                   | `10.7.18.206` | dnsmasq       |
| Mac 2   | Reverse Proxy / Load Balancer | `10.7.18.80`  | nginx         |
| Mac 3   | Backend A                     | `10.7.3.174`  | Node.js :3001 |
| Mac 4   | Backend B                     | `10.7.14.88`  | Node.js :3002 |

Application:

```text id="s2q6bj"
https://app.teamX.test
```

Request flow:

```text id="w2k7xq"
Client
  ↓
Mac 1 — DNS
  ↓
Mac 2 — nginx
  ├──→ Mac 3 — Backend A
  └──→ Mac 4 — Backend B
```

## 2. Session Startup

Start the services in this order.

### Mac 1 — DNS

```bash id="7t8q1c"
brew services start dnsmasq
```

Verify:

```bash id="g6f1j2"
brew services list | grep dnsmasq
sudo lsof -nP -iUDP:53 -iTCP:53
```

Test:

```bash id="v5c9x3"
dig @10.7.18.206 app.teamX.test +short
```

Expected:

```text id="n4b8s6"
10.7.18.80
```

### Mac 3 — Backend A

```bash id="m3s7p1"
cd ~/cn-project/cn-backend
BACKEND=A PORT=3001 node server.js
```

Verify from Mac 2 or another client:

```bash id="q8r2v4"
curl -i http://10.7.3.174:3001/api/status
```

Expected:

```text id="d1f6k9"
X-Backend: A
```

### Mac 4 — Backend B

```bash id="h4n7w2"
cd ~/cn-project/cn-backend
BACKEND=B PORT=3002 node server.js
```

Verify:

```bash id="c5m9q1"
curl -i http://10.7.14.88:3002/api/status
```

Expected:

```text id="j7v3p8"
X-Backend: B
```

### Mac 2 — nginx

Validate:

```bash id="k2x6r4"
sudo nginx -t
```

Then reload:

```bash id="p9w1m5"
sudo nginx -s reload
```

## 3. End-to-End Health Check

From a client:

```bash id="b4q8s2"
dig app.teamX.test +short
```

Expected:

```text id="t6n3v9"
10.7.18.80
```

Then:

```bash id="r1k5y7"
curl -i https://app.teamX.test/api/status
```

Expected:

```text id="x8c2m4"
HTTP/2 200
```

with either:

```text id="e7p3q9"
X-Backend: A
```

or:

```text id="u2v6k8"
X-Backend: B
```

## 4. DNS Diagnosis

### Check Mac 1 DNS service

```bash id="f5j8n2"
sudo lsof -nP -iUDP:53 -iTCP:53
```

### Query Mac 1 directly

```bash id="c9r4w6"
dig @10.7.18.206 app.teamX.test +short
```

### Check client DNS configuration

```bash id="m7q2x5"
scutil --dns | grep -E 'nameserver\[[0-9]+\]'
```

or:

```bash id="a3v8k1"
networksetup -getdnsservers Wi-Fi
```

The client should use:

```text id="n5s9d4"
10.7.18.206
```

### If DNS fails

Check:

1. Mac 1 is connected to the private LAN.
2. dnsmasq is running.
3. Port 53 is listening.
4. `dnsmasq.conf` contains the correct `app.teamX.test` record.
5. The client is using Mac 1 as its DNS server.
6. Mac 2's current IP matches the DNS record.

## 5. Backend Diagnosis

### Backend A

Test directly:

```bash id="q6m1x8"
curl -i --max-time 5 http://10.7.3.174:3001/api/status
```

### Backend B

```bash id="w3p7k2"
curl -i --max-time 5 http://10.7.14.88:3002/api/status
```

If either request fails:

* Check that the corresponding backend process is running.
* Check the correct port.
* Check the Mac's current LAN IP.
* Check macOS firewall permissions.
* Check that the backend listens on `0.0.0.0`, not only `127.0.0.1`.

## 6. nginx Diagnosis

Validate configuration:

```bash id="z4c8n1"
sudo nginx -t
```

If successful:

```text id="v6m2q9"
syntax is ok
test is successful
```

Reload:

```bash id="p1x5r7"
sudo nginx -s reload
```

Check nginx service:

```bash id="h8k3w6"
brew services list | grep nginx
```

Test the public endpoint:

```bash id="y2q9m4"
curl -i https://app.teamX.test/api/status
```

## 7. Load Balancer Diagnosis

Run multiple requests:

```bash id="s5v1k8"
for i in 1 2 3 4 5 6; do
  curl -s https://app.teamX.test/api/status | grep '"backend"'
done
```

Confirm that responses include both:

```text id="a7d2p5"
"backend":"A"
```

and:

```text id="c4n8y1"
"backend":"B"
```

The exact request order does not need to alternate.

If only one backend responds:

1. Test Backend A directly.
2. Test Backend B directly.
3. Check the nginx upstream configuration.
4. Check that both backend IP addresses are current.
5. Reload nginx after configuration changes.

## 8. TLS Diagnosis

Verify the certificate:

```bash id="r6x2m9"
openssl verify \
  -CAfile certs/rootCA.pem \
  certs/server.crt
```

Expected:

```text id="k1v7q3"
server.crt: OK
```

Check certificate details:

```bash id="n8p4s6"
openssl x509 \
  -in certs/server.crt \
  -noout \
  -subject \
  -issuer \
  -ext subjectAltName
```

The certificate should contain:

```text id="m3w9x2"
DNS:app.teamX.test
DNS:api.teamX.test
```

Test HTTPS:

```bash id="q5r1k7"
curl -i https://app.teamX.test/api/status
```

Do not use `-k` when testing normal certificate validation.

## 9. HTTP Version Diagnosis

Test HTTP/1.1:

```bash id="b8v2m5"
curl -sI --http1.1 https://app.teamX.test/api/status | head -1
```

Test HTTP/2:

```bash id="d6q9x3"
curl -sI --http2 https://app.teamX.test/api/status | head -1
```

Expected:

```text id="w1n7p4"
HTTP/1.1 200 OK
HTTP/2 200
```

## 10. Caching Diagnosis

Test the cached endpoint:

```bash id="f3m8r2"
curl -i https://app.teamX.test/api/cached
```

Verify:

```text id="y5q1v9"
Cache-Control: public, max-age=60
ETag: <ETag value>
```

Then send a conditional request using the returned ETag:

```bash id="k7s2x6"
curl -i \
  -H 'If-None-Match: <ETAG>' \
  https://app.teamX.test/api/cached
```

Expected:

```text id="p4n8w1"
HTTP/2 304
```

## 11. Backend Failure and Recovery

### Stop Backend A

On Mac 3:

```text id="c2v7m5"
Ctrl+C
```

Verify direct access fails:

```bash id="r9x3k6"
curl --max-time 5 http://10.7.3.174:3001/api/status
```

Then test through nginx:

```bash id="n1q8s4"
curl -i https://app.teamX.test/api/status
```

Backend B should remain available if nginx's upstream retry/failover configuration allows it.

### Restart Backend A

```bash id="z6m2p8"
BACKEND=A PORT=3001 node server.js
```

Verify:

```bash id="v4k9x1"
curl -i http://10.7.3.174:3001/api/status
```

### Stop Backend B

On Mac 4:

```text id="q3w7n5"
Ctrl+C
```

Verify direct access fails:

```bash id="a8r2m6"
curl --max-time 5 http://10.7.14.88:3002/api/status
```

Then test through nginx.

### Restart Backend B

```bash id="h5x1v8"
BACKEND=B PORT=3002 node server.js
```

Verify:

```bash id="m9c4q7"
curl -i http://10.7.14.88:3002/api/status
```

## 12. IP Address Changes

The private LAN may assign different IP addresses.

Check each Mac's current address:

```bash id="s7n2k5"
ifconfig en0 | grep -E 'inet |ether '
```

Check the default gateway:

```bash id="p3x8m1"
route -n get default | grep gateway
```

If an IP changes:

### Update DNS

Modify:

```text id="w6q1r4"
dns/dnsmasq.conf
```

so that:

```text id="d9v3k7"
app.teamX.test → CURRENT_MAC2_IP
```

Restart dnsmasq:

```bash id="e2m8s5"
brew services restart dnsmasq
```

### Update nginx

Modify:

```text id="r4k7x1"
nginx/teamX.conf
```

with the current Backend A and Backend B IP addresses.

Validate:

```bash id="c8p2m6"
sudo nginx -t
```

Reload:

```bash id="y5n9q3"
sudo nginx -s reload
```

### Re-test

```bash id="u1v6k8"
dig app.teamX.test +short
curl -i https://app.teamX.test/api/status
```

## 13. Git / Repository Recovery

Before making configuration changes:

```bash id="f7m3q9"
git status
git pull --rebase origin main
```

After changes:

```bash id="x2k8v4"
git add .
git commit -m "Update project configuration"
git push origin main
```

Do not use `git push --force` unless the repository maintainers explicitly require it.

## 14. Quick Recovery Checklist

If the application is not working, check in this order:

```text id="n3r7w5"
1. Check Mac IP addresses
        ↓
2. Check dnsmasq
        ↓
3. Test app.teamX.test DNS resolution
        ↓
4. Test Backend A directly
        ↓
5. Test Backend B directly
        ↓
6. Run nginx -t
        ↓
7. Reload nginx
        ↓
8. Test HTTPS
        ↓
9. Test load balancing
        ↓
10. Check TLS/cache behavior
```

## 15. Important Security Rules

Never commit:

* Private keys
* `.key` files
* `.pem` files containing private material
* Credentials
* Passwords
* API tokens
* `.env` files containing secrets

The `.gitignore` file is configured to prevent common sensitive files and generated artifacts from being committed.

Evidence should be stored only in the appropriate `evidence/` directories.
