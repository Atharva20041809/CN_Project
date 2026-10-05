# Backend Servers — Mac 3 and Mac 4

This directory contains the two application servers used in the Private Network Service Platform project.

* **Backend A** runs on Mac 3 and listens on TCP port `3001`.
* **Backend B** runs on Mac 4 and listens on TCP port `3002`.
* Both backends are Node.js/Express applications.
* Both are accessed by the nginx reverse proxy and load balancer running on Mac 2.

## Student Details

* **Name:** Shubhaang Kataruka
* **Enrollment Number:** 2401010450

## Network Architecture

The Phase 1 request flow is:

```text
Client
   │
   ▼
Private DNS
   │
   ▼
Mac 2 — nginx Reverse Proxy / Load Balancer
   │
   ├──────────────► Mac 3 — Backend A :3001
   │
   └──────────────► Mac 4 — Backend B :3002
```

The application hostname is:

```text
app.teamX.test
```

The private DNS record resolves it to Mac 2:

```text
app.teamX.test → 10.7.18.80
```

## Backend A — Mac 3

| Property           | Value        |
| ------------------ | ------------ |
| Machine            | Mac 3        |
| LAN IP             | `10.7.3.174` |
| Backend Identifier | A            |
| Port               | `3001`       |
| Protocol           | HTTP         |
| Runtime            | Node.js      |
| Framework          | Express      |

Backend A listens on:

```text
0.0.0.0:3001
```

Mac 2's nginx upstream for Backend A is:

```text
10.7.3.174:3001
```

## Backend B — Mac 4

| Property           | Value        |
| ------------------ | ------------ |
| Machine            | Mac 4        |
| LAN IP             | `10.7.14.88` |
| Backend Identifier | B            |
| Port               | `3002`       |
| Protocol           | HTTP         |
| Runtime            | Node.js      |
| Framework          | Express      |

Backend B listens on:

```text
0.0.0.0:3002
```

Mac 2's nginx upstream for Backend B is:

```text
10.7.14.88:3002
```

## Technology

Both backend servers use:

* Node.js
* Express
* HTTP/REST
* JSON responses
* TCP

## API Endpoints

### GET `/`

Confirms that the backend is running.

### GET `/api/status`

Returns the backend identifier and health status.

Backend A:

```json
{
  "backend": "A",
  "status": "ok"
}
```

Backend B:

```json
{
  "backend": "B",
  "status": "ok"
}
```

Responses include the corresponding header:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

### GET `/api/cached`

Provides the cache demonstration endpoint.

Responses include:

```text
Cache-Control: public, max-age=60
ETag: <ETag value>
```

A request with a matching `If-None-Match` header returns:

```text
HTTP 304 Not Modified
```

with no response body.

## Setup and Run

### Backend A — Mac 3

On Mac 3:

```bash
cd ~/cn-project/cn-backend
BACKEND=A PORT=3001 node server.js
```

Expected output:

```text
Backend A listening on 0.0.0.0:3001
```

### Backend B — Mac 4

On Mac 4:

```bash
cd ~/cn-project/cn-backend
BACKEND=B PORT=3002 node server.js
```

Expected output:

```text
Backend B listening on 0.0.0.0:3002
```

Keep the server terminals open while testing.

Stop either backend with:

```text
Ctrl+C
```

## Local Testing

### Backend A

On Mac 3:

```bash
curl -i http://127.0.0.1:3001/api/status
```

### Backend B

On Mac 4:

```bash
curl -i http://127.0.0.1:3002/api/status
```

Both should return HTTP 200 and the appropriate `X-Backend` header.

## LAN Testing

From Mac 2:

### Test Backend A

```bash
curl -i --max-time 5 http://10.7.3.174:3001/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: A
```

### Test Backend B

```bash
curl -i --max-time 5 http://10.7.14.88:3002/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: B
```

## Load Balancing Test

The public application endpoint is served through nginx on Mac 2:

```text
https://app.teamX.test/api/status
```

From a client such as Mac 4:

```bash
for i in 1 2 3 4 5 6; do
  curl -s https://app.teamX.test/api/status | grep '"backend"'
done
```

Responses should show requests being distributed between:

```text
Backend A
Backend B
```

The exact order does not have to alternate strictly.

## Caching Test

Test the cache endpoint:

```bash
curl -i https://app.teamX.test/api/cached
```

The response should contain:

```text
Cache-Control: public, max-age=60
ETag: <ETag value>
```

Use the returned ETag for a conditional request:

```bash
curl -i -H 'If-None-Match: <ETAG>' \
  https://app.teamX.test/api/cached
```

A matching ETag should produce:

```text
HTTP/2 304
```

with no response body.

## Failure and Recovery Demonstration

### Backend A Failure

On Mac 3, stop Backend A:

```text
Ctrl+C
```

Direct access to:

```text
http://10.7.3.174:3001/api/status
```

should no longer succeed.

Do not stop Backend B.

Then test the application through nginx:

```bash
curl -i https://app.teamX.test/api/status
```

Depending on nginx's upstream retry configuration, requests should continue through Backend B or may temporarily return an upstream error.

### Backend B Failure

Similarly, stop Backend B on Mac 4:

```text
Ctrl+C
```

Direct access to:

```text
http://10.7.14.88:3002/api/status
```

should fail.

Backend A should remain available.

### Recovery

Restart Backend A on Mac 3:

```bash
BACKEND=A PORT=3001 node server.js
```

Restart Backend B on Mac 4:

```bash
BACKEND=B PORT=3002 node server.js
```

Verify both direct endpoints and then repeat the nginx load-balancing test.
