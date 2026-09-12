# New API production deployment

This folder contains a production-oriented Docker Compose deployment for New API on Tencent Lighthouse.

## Values to replace

- `api.jiatuc.cn`: production subdomain.
- `CHANGE_ME_*`: replace with strong generated secrets before starting services.

Generate secrets on the server:

```bash
openssl rand -hex 32
```

Run it four times and use different values for:

- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `SESSION_SECRET`
- `CRYPTO_SECRET`

## DNS first

Create this DNS record at your domain provider:

```text
Type: A
Host: api
Value: YOUR_SERVER_PUBLIC_IP
TTL: Auto or 600
```

Wait until this returns your server IP:

```bash
dig +short api.yourdomain.com
```

## Server setup check

The Tencent Lighthouse server already has Docker and Docker Compose. Verify:

```bash
docker --version
docker compose version
```

## Deploy New API

Paste the contents of `tencent-lighthouse-install.sh` into the Tencent Cloud web terminal, or upload and run it:

```bash
bash tencent-lighthouse-install.sh
```

Then open:

```text
https://api.jiatuc.cn
```

## Security checks

The app should only bind to localhost:

```bash
ss -lntp | grep ':3000'
```

The public firewall/security group should allow:

- TCP 22 for SSH
- TCP 80 for Caddy HTTP challenge and redirect
- TCP 443 for HTTPS

Do not expose:

- TCP 3000
- TCP 5432
- TCP 6379


