# Private Network Service Platform — Setup Guide

This document describes how to set up and run the Private Network Service Platform across the four Macs.

## 1. Project Architecture

The project consists of four machines:

| Machine | Role                          | IP Address    | Service                 |
| ------- | ----------------------------- | ------------- | ----------------------- |
| Mac 1   | Private DNS                   | `10.7.18.206` | dnsmasq                 |
| Mac 2   | Reverse Proxy / Load Balancer | `10.7.18.80`  | nginx                   |
| Mac 3   | Backend A                     | `10.7.3.174`  | Node.js / Express :3001 |
| Mac 4   | Backend B                     | `10.7.14.88`  | Node.js / Express :3002 |

The request flow is:

```text
Client
   │
   ▼
Mac 1 — Private DNS
   │
   │ app.teamX.test → 10.7.18.80
   ▼
Mac 2 — nginx
   │
   ├──────────────► Mac 3 — Backend A :3001
   │
   └──────────────► Mac 4 — Backend B :3002
```

## 2. Prerequisites

All machines should:

* Be connected to the same private LAN.
* Be able to communicate with the required machines.
* Have their current LAN IP addresses verified before starting the services.
* Have Homebrew available where required.

Required software:

* Node.js and npm on Mac 3 and Mac 4
* dnsmasq on Mac 1
* nginx on Mac 2
* OpenSSL on Mac 2
* Git on all machines used for repository management

## 3. Clone the Repository

On each machine that needs the project files:

```bash
git clone https://github.com/Atharva20041809/CN_Project.git
cd CN_Project
```

If the repository already exists locally:

```bash
git pull origin main
```

## 4. Mac 1 — Private DNS

Mac 1 runs dnsmasq and provides private DNS resolution.

The project configuration is:

```text
dns/dnsmasq.conf
```

The important DNS mapping is:

```text
app.teamX.test → 10.7.18.80
```

The DNS server's IP is:

```text
10.7.18.206
```

Install dnsmasq if required:

```bash
brew install dnsmasq
```

Copy or configure the project configuration according to the local Homebrew dnsmasq configuration path.

Start dnsmasq:

```bash
brew services start dnsmasq
```

Check its status:

```bash
brew services list | grep dnsmasq
```

Verify that DNS port 53 is listening:

```bash
sudo lsof -nP -iUDP:53 -iTCP:53
```

Test the private DNS record:

```bash
dig @10.7.18.206 app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

## 5. Mac 2 — nginx

Mac 2 provides HTTPS termination, reverse proxying, and load balancing.

The nginx configuration is:

```text
nginx/teamX.conf
```

The backend upstreams are:

```text
Backend A → 10.7.3.174:3001
Backend B → 10.7.14.88:3002
```

Install nginx if required:

```bash
brew install nginx
```

Place the project nginx configuration in the appropriate nginx configuration directory or include it from the main nginx configuration.

Validate the configuration:

```bash
sudo nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

Start nginx:

```bash
brew services start nginx
```

After configuration changes:

```bash
sudo nginx -t
sudo nginx -s reload
```

## 6. TLS Certificates

Certificate configuration files are stored in:

```text
certs/
├── ca.cnf
├── leaf.cnf
└── make-certs.sh
```

Make the certificate-generation script executable:

```bash
chmod +x certs/make-certs.sh
```

Generate the certificates:

```bash
./certs/make-certs.sh
```

The generated private keys and certificate material must not be committed to Git.

Verify the server certificate against the local Root CA:

```bash
openssl verify \
  -CAfile certs/rootCA.pem \
  certs/server.crt
```

Expected:

```text
certs/server.crt: OK
```

Verify the certificate SANs:

```bash
openssl x509 \
  -in certs/server.crt \
  -noout \
  -subject \
  -issuer \
  -ext subjectAltName
```

The certificate should contain:

```text
DNS:app.teamX.test
DNS:api.teamX.test
```

## 7. Mac 3 — Backend A

Backend A runs on Mac 3 on TCP port `3001`.

From the project directory:

```bash
cd cn-backend
```

Start Backend A:

```bash
BACKEND=A PORT=3001 node server.js
```

Expected:

```text
Backend A listening on 0.0.0.0:3001
```

Test locally:

```bash
curl -i http://127.0.0.1:3001/api/status
```

Test from another machine:

```bash
curl -i http://10.7.3.174:3001/api/status
```

Expected response:

```text
HTTP/1.1 200 OK
X-Backend: A
```

## 8. Mac 4 — Backend B

Backend B runs on Mac 4 on TCP port `3002`.

From the project directory:

```bash
cd cn-backend
```

Start Backend B:

```bash
BACKEND=B PORT=3002 node server.js
```

Expected:

```text
Backend B listening on 0.0.0.0:3002
```

Test locally:

```bash
curl -i http://127.0.0.1:3002/api/status
```

Test from another machine:

```bash
curl -i http://10.7.14.88:3002/api/status
```

Expected response:

```text
HTTP/1.1 200 OK
X-Backend: B
```

## 9. Configure Client DNS

Clients that need to resolve the private hostname should use Mac 1 as their DNS server:

```text
10.7.18.206
```

On macOS, verify the configured DNS server:

```bash
networksetup -getdnsservers Wi-Fi
```

or:

```bash
scutil --dns | grep -E 'nameserver\[[0-9]+\]'
```

Test normal DNS resolution:

```bash
dig app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

## 10. End-to-End HTTPS Test

Once DNS, nginx, TLS, and both backends are running:

```bash
curl -i https://app.teamX.test/api/status
```

A successful response should return:

```text
HTTP/2 200
```

and include:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

## 11. Load Balancing Test

Run multiple requests:

```bash
for i in 1 2 3 4 5 6; do
  curl -s https://app.teamX.test/api/status | grep '"backend"'
done
```

The responses should demonstrate that nginx can route requests to both Backend A and Backend B.

The exact order does not have to alternate between A and B.

## 12. Caching Test

Test the cache endpoint:

```bash
curl -i https://app.teamX.test/api/cached
```

The response should include:

```text
Cache-Control: public, max-age=60
ETag: <ETag value>
```

Use the returned ETag for a conditional request:

```bash
curl -i \
  -H 'If-None-Match: <ETAG>' \
  https://app.teamX.test/api/cached
```

A matching ETag should return:

```text
HTTP/2 304
```

with no response body.

## 13. Basic Connectivity Checks

From Mac 2, verify Backend A:

```bash
curl -i --max-time 5 http://10.7.3.174:3001/api/status
```

Verify Backend B:

```bash
curl -i --max-time 5 http://10.7.14.88:3002/api/status
```

From Mac 2, verify DNS:

```bash
dig @10.7.18.206 app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

## 14. Recommended Startup Order

For a fresh project session, start the services in this order:

### Mac 1

Start dnsmasq:

```bash
brew services start dnsmasq
```

### Mac 3

Start Backend A:

```bash
cd ~/cn-project/cn-backend
BACKEND=A PORT=3001 node server.js
```

### Mac 4

Start Backend B:

```bash
cd ~/cn-project/cn-backend
BACKEND=B PORT=3002 node server.js
```

### Mac 2

Validate and start/reload nginx:

```bash
sudo nginx -t
sudo nginx -s reload
```

### Client

Verify:

```bash
dig app.teamX.test +short
curl -i https://app.teamX.test/api/status
```

## 15. Important Notes

The IP addresses documented above were used during the project setup. If the private LAN assigns different addresses later, update:

* `dns/dnsmasq.conf`
* `nginx/teamX.conf`
* Client DNS configuration
* Documentation

Do not commit private keys, credentials, or generated certificate private material.

Evidence files belong under the appropriate `evidence/` directories and should be kept separate from source configuration.
