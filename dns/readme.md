# DNS Server — Mac 1

Mac 1 provides the private DNS service for the Private Network Service Platform project. It runs `dnsmasq` and resolves the project's private hostname to the nginx server running on Mac 2.

## Student Details

* **Name:** Tanish Yadav
* **Enrollment Number:** 2401010474
* **Role:** Mac 1 — Private DNS Server
* **DNS Server:** `dnsmasq`
* **DNS Port:** `53`

## Network Details

| Property        | Value         |
| --------------- | ------------- |
| Machine         | Mac 1         |
| LAN IP          | `10.7.18.206` |
| DNS Service     | dnsmasq       |
| DNS Port        | 53            |
| Default Gateway | `10.7.0.1`    |

## DNS Role

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
   ├──────────► Backend A — Mac 3 :3001
   │
   └──────────► Backend B — Mac 4 :3002
```

The private DNS record is:

```text
app.teamX.test → 10.7.18.80
```

Mac 2 (`10.7.18.80`) is the nginx reverse proxy and load balancer.

## Configuration

The dnsmasq configuration file is:

```text
/opt/homebrew/etc/dnsmasq.conf
```

The relevant private DNS configuration is:

```text
address=/app.teamX.test/10.7.18.80
```

dnsmasq listens for DNS queries on port `53`.

## Starting DNS Service

If dnsmasq is installed through Homebrew, start it with:

```bash
brew services start dnsmasq
```

To restart it after configuration changes:

```bash
brew services restart dnsmasq
```

To check its status:

```bash
brew services list | grep dnsmasq
```

## Verify DNS Service

Check that dnsmasq is listening on port 53:

```bash
sudo lsof -nP -iUDP:53 -iTCP:53
```

Mac 1 should show dnsmasq listening on:

```text
10.7.18.206:53
```

## DNS Testing

From Mac 1:

```bash
dig @10.7.18.206 app.teamX.test +short
```

Expected result:

```text
10.7.18.80
```

From another machine on the private LAN, such as Mac 3 or Mac 4:

```bash
dig @10.7.18.206 app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

## System DNS Configuration

Client machines can use Mac 1 as their DNS server.

Verify the configured DNS server on macOS with:

```bash
networksetup -getdnsservers Wi-Fi
```

Expected:

```text
10.7.18.206
```

After configuring the client to use Mac 1, test normal DNS resolution:

```bash
dig app.teamX.test +short
```

Expected:

```text
10.7.18.80
```

Public DNS resolution should continue to work through dnsmasq's upstream DNS configuration. For example:

```bash
dig google.com +short
```

## Troubleshooting

Check whether dnsmasq is listening:

```bash
sudo lsof -nP -iUDP:53 -iTCP:53
```

Test DNS directly against Mac 1:

```bash
dig @10.7.18.206 app.teamX.test +short
```

Test connectivity to the DNS server from another machine:

```bash
nc -vz 10.7.18.206 53
```

Check the client's configured DNS server:

```bash
scutil --dns | grep -E 'nameserver\[[0-9]+\]'
```

If the private hostname does not resolve, verify that:

1. Mac 1 is connected to the private LAN.
2. dnsmasq is running.
3. Port 53 is accessible.
4. `/opt/homebrew/etc/dnsmasq.conf` contains the correct `address` record.
5. The client is configured to use `10.7.18.206` as its DNS server.
6. The hostname resolves to the current Mac 2 IP address.

## Security

The DNS server is intended for the private project LAN.

Do not commit:

* Private keys
* Credentials
* Secrets
* TLS certificate private material
* Unnecessary system configuration files

Only the project-specific `dnsmasq.conf` required to reproduce the DNS setup should be stored in this repository.