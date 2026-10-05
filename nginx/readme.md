# nginx — Mac 2

Mac 2 acts as the **reverse proxy and load balancer** for the Private Network Service Platform project. It receives client HTTPS requests for `app.teamX.test`, terminates TLS, and distributes application requests between Backend A on Mac 3 and Backend B on Mac 4.

## Student Details

* **Name:** Abhishek Rana
* **Enrollment Number:** 2401010021
* **Role:** Mac 2 — nginx Reverse Proxy / Load Balancer
* **Server IP:** `10.7.18.80`

## Network Role

The Phase 1 request flow is:

```text
Client
   │
   ▼
Private DNS — Mac 1
   │
   │ app.teamX.test → 10.7.18.80
   ▼
Mac 2 — nginx
   │
   ├──────────► Mac 3 — Backend A :3001
   │
   └──────────► Mac 4 — Backend B :3002
```

nginx provides:

* Reverse proxy functionality
* Load balancing
* HTTPS/TLS termination
* HTTP/2 support
* Cache-control handling
* Backend failover/retry behavior

## Network Details

| Property             | Value             |
| -------------------- | ----------------- |
| Machine              | Mac 2             |
| LAN IP               | `10.7.18.80`      |
| Service              | nginx             |
| HTTPS Port           | `8443`            |
| Application Hostname | `app.teamX.test`  |
| Backend A            | `10.7.3.174:3001` |
| Backend B            | `10.7.14.88:3002` |

## nginx Configuration

The project nginx configuration is stored as:

```text
nginx/teamX.conf
```

The configuration defines the application hostname:

```text
app.teamX.test
```

and proxies requests to the backend pool:

```text
Backend A → 10.7.3.174:3001
Backend B → 10.7.14.88:3002
```

## Load Balancing

nginx distributes requests between Backend A and Backend B.

Example:

```bash
for i in 1 2 3 4; do
  curl -s https://app.teamX.test/api/status | grep '"backend"'
done
```

Possible output:

```text
{"backend":"A","status":"ok",...}
{"backend":"A","status":"ok",...}
{"backend":"B","status":"ok",...}
{"backend":"A","status":"ok",...}
```

The order is not required to alternate strictly.

The backend can also be identified through the response header:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

## HTTPS and TLS

nginx terminates HTTPS connections for `app.teamX.test`.

The server certificate is issued by the project's local Certificate Authority:

```text
teamX Local Root CA
```

The certificate contains the required SANs:

```text
DNS:app.teamX.test
DNS:api.teamX.test
```

Clients can access the application using:

```text
https://app.teamX.test
```

The TLS configuration supports HTTP/1.1 and HTTP/2.

## Testing HTTPS

From a client machine:

```bash
curl -i https://app.teamX.test/api/status
```

A successful response should return:

```text
HTTP/2 200
```

and an `X-Backend` header identifying the backend that handled the request.

HTTP/1.1 can be tested with:

```bash
curl -sI --http1.1 https://app.teamX.test/api/status | head -1
```

HTTP/2 can be tested with:

```bash
curl -sI --http2 https://app.teamX.test/api/status | head -1
```

## Caching

The `/api/cached` endpoint provides cache validation through HTTP headers.

Test with:

```bash
curl -i https://app.teamX.test/api/cached
```

The response includes:

```text
Cache-Control: public, max-age=60
ETag: <ETag value>
```

A conditional request using the returned ETag can be tested with:

```bash
curl -i -H 'If-None-Match: <ETAG>' \
  https://app.teamX.test/api/cached
```

A matching ETag should result in:

```text
HTTP/2 304
```

with no response body.

## nginx Configuration Validation

Before reloading nginx, validate the configuration:

```bash
sudo nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

## Starting and Reloading nginx

Check the nginx service:

```bash
brew services list | grep nginx
```

Start nginx if required:

```bash
brew services start nginx
```

After configuration changes, test the configuration:

```bash
sudo nginx -t
```

Then reload nginx:

```bash
sudo nginx -s reload
```

## Backend Connectivity

Mac 2 can directly test Backend A:

```bash
curl -i --max-time 5 http://10.7.3.174:3001/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: A
```

Backend B:

```bash
curl -i --max-time 5 http://10.7.14.88:3002/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: B
```

These tests verify that nginx can reach both application servers directly.

## Failure and Recovery

If Backend A is stopped on Mac 3, direct requests to:

```text
10.7.3.174:3001
```

should fail.

Backend B should remain available.

If Backend B is stopped on Mac 4, direct requests to:

```text
10.7.14.88:3002
```

should fail while Backend A remains available.

After restarting the failed backend, verify its `/api/status` endpoint and repeat the load-balancing test through:

```text
https://app.teamX.test/api/status
```

Depending on the nginx upstream configuration, unavailable backends may be retried or may result in an upstream error such as `502 Bad Gateway`.

## Security

Do not commit:

* Private keys
* Credentials
* Secrets
* `.key` files
* `.pem` files containing private material

TLS certificates and private cryptographic material should remain protected according to the project's `.gitignore` rules.
