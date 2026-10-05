# Private Network Service Platform

TeamX - A private-network web service platform built using **four physical macOS laptops on the same LAN**.

The project demonstrates private DNS resolution, reverse proxying, HTTPS/TLS, load balancing, backend services, HTTP caching, packet-level analysis, and failure/recovery scenarios.

## Infrastructure Type

**Type 1 — 4 physical macOS laptops on the same LAN**

## Student Details

| Machine | Student        | Enrollment Number | Role                                  |
| ------- | -------------- | ----------------- | ------------------------------------- |
| Mac 1   | Tanish Roa     | 2401010474        | Private DNS                           |
| Mac 2   | Abhishek Rana  | 2401010021        | nginx / Reverse Proxy / Load Balancer |
| Mac 3   | Atharva Tiwari | 2401010113        | Backend Server A                      |
| Mac 4   | Varun Sharma   | 2401010497        | Backend Server B                      |

## Project Architecture

```text
                         Private LAN
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
   Mac 1 — DNS          Mac 2 — nginx       Backend Servers
   10.7.18.206          10.7.18.80                │
   dnsmasq                   │                     │
                             │              ┌──────┴──────┐
                             │              │             │
                             ▼              ▼             ▼
                       HTTPS :443       Mac 3          Mac 4
                                      Backend A       Backend B
                                      :3001           :3002
                                      10.7.3.174      10.7.14.88
```

## Request Flow

The normal application request flow is:

```text
Client
   │
   │ DNS query
   ▼
Mac 1 — dnsmasq
   │
   │ app.teamX.test → 10.7.18.80
   ▼
Mac 2 — nginx :443
   │
   ├──────────────► Mac 3 — Backend A :3001
   │
   └──────────────► Mac 4 — Backend B :3002
```

The public application hostname used within the private network is:

```text
https://app.teamX.test
```

## Components

### Mac 1 — Private DNS

Mac 1 runs **dnsmasq** and provides private DNS resolution.

```text
DNS Server: 10.7.18.206
Hostname:   app.teamX.test
Resolves:   10.7.18.80
```

The private DNS record ensures that clients access the nginx server rather than connecting directly to either backend.

### Mac 2 — nginx

Mac 2 runs **nginx** as the HTTPS reverse proxy and load balancer.

```text
IP Address: 10.7.18.80
HTTPS Port: 443
```

nginx terminates TLS and forwards application requests to the backend servers.

```text
Backend A → 10.7.3.174:3001
Backend B → 10.7.14.88:3002
```

### Mac 3 — Backend A

Backend A is a Node.js/Express application.

```text
IP Address: 10.7.3.174
Port:       3001
Identifier: A
```

### Mac 4 — Backend B

Backend B is a Node.js/Express application.

```text
IP Address: 10.7.14.88
Port:       3002
Identifier: B
```

Both backends expose the same application API while returning their backend identifier through the `X-Backend` response header and JSON response.

## API Endpoints

### `GET /`

Basic backend availability endpoint.

### `GET /api/status`

Returns the current backend identifier and status.

Example:

```json
{
  "backend": "A",
  "status": "ok"
}
```

Backend B returns:

```json
{
  "backend": "B",
  "status": "ok"
}
```

Responses include:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

### `GET /api/cached`

Demonstrates HTTP caching and ETag validation.

The response uses:

```text
Cache-Control: public, max-age=60
ETag: <ETag value>
```

A request containing the matching `If-None-Match` header returns:

```text
HTTP 304 Not Modified
```

## TLS / HTTPS

The project uses a locally generated Root CA and server certificate.

The certificate configuration is maintained under:

```text
certs/
├── ca.cnf
├── leaf.cnf
└── make-certs.sh
```

The application certificate covers:

```text
app.teamX.test
api.teamX.test
```

HTTPS is terminated by nginx on:

```text
10.7.18.80:443
```

Private keys and generated certificate files are intentionally excluded from Git.

## Repository Structure

```text
cn-project/
├── README.md
├── .gitignore
│
├── cn-backend/
│   ├── cn-backend-a/
│   └── cn-backend-b/
│
├── dns/
│   ├── dnsmasq.conf
│   └── README.md
│
├── nginx/
│   ├── teamX.conf
│   └── README.md
│
├── certs/
│   ├── ca.cnf
│   ├── leaf.cnf
│   ├── make-certs.sh
│   └── README.md
│
├── docs/
│   ├── SETUP.md
│   └── RUNBOOK.md
│
└── evidence/
    ├── A-lan/
    ├── B-dns/
    ├── C-backends/
    ├── D-loadbalancer/
    ├── E-tls/
    ├── F-caching/
    ├── G-wireshark/
    └── H-failures/
```

## Evidence

The `evidence/` directory contains screenshots and supporting evidence for the major project components:

* **A — LAN:** IP addressing and LAN connectivity
* **B — DNS:** dnsmasq and private hostname resolution
* **C — Backends:** Backend A and Backend B operation
* **D — Load Balancer:** nginx distribution across both backends
* **E — TLS:** HTTPS and certificate validation
* **F — Caching:** Cache-Control, ETag, and 304 responses
* **G — Wireshark:** DNS, TLS, and backend traffic analysis
* **H — Failures:** Failure demonstrations and service recovery

## Verification

A complete end-to-end test can be performed with:

```bash
dig app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

Then:

```bash
curl -i https://app.teamX.test/api/status
```

Expected:

```text
HTTP/2 200
```

with either:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

Multiple requests demonstrate load balancing:

```bash
for i in 1 2 3 4 5 6; do
  curl -s https://app.teamX.test/api/status
  echo
done
```

## Documentation

Detailed setup and operational procedures are available in:

```text
docs/SETUP.md
docs/RUNBOOK.md
```

`SETUP.md` describes how to configure and start the infrastructure.

`RUNBOOK.md` provides troubleshooting, diagnosis, failure, recovery, DNS, nginx, TLS, and backend procedures.

## Security and Repository Policy

The repository must not contain:

* Private keys
* `.key` files
* Private certificate material
* Credentials
* Passwords
* API tokens
* `.env` files containing secrets

The `.gitignore` file excludes sensitive and generated files from Git.

## Project Goal

The goal of this project is to demonstrate how multiple physical machines on a private LAN can work together to provide a complete network service platform:

```text
Private DNS
     ↓
HTTPS / TLS
     ↓
Reverse Proxy
     ↓
Load Balancing
     ↓
Backend Services
     ↓
HTTP Caching
     ↓
Network Analysis
     ↓
Failure & Recovery
```

This project combines these components into one working private-network service architecture using four physical macOS machines.
