# 🛡️ Caddy-Sec: The Hardened Web Proxy

A pre-built, production-ready [Caddy Web Server](https://caddyserver.com/) image compiled with enterprise-grade security modules. No need to build from source — just pull and deploy.

**Docker Hub:** [hub.docker.com/r/dhimanparas20/caddy](https://hub.docker.com/r/dhimanparas20/caddy)

```bash
docker pull dhimanparas20/caddy:latest
```

> ✅ Supports **AMD64 (x86_64)** and **ARM64 (aarch64/Raspberry Pi)**
> — a single `docker pull` automatically fetches the correct architecture.

---

## 📦 What's Inside

This image is built on top of the official `caddy:latest` image with the following modules compiled in via [xcaddy](https://github.com/caddyserver/xcaddy):

| Module | Purpose |
|---|---|
| [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | Intelligent per-IP rate limiting with sliding windows |
| [corazawaf/coraza-caddy/v2](https://github.com/corazawaf/coraza-caddy) | Web Application Firewall — blocks SQLi, XSS, and vulnerability scanners using OWASP rules |
| [hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) | CrowdSec integration — auto-bans known malicious IPs, botnets, and DDoS nodes |

### Built-in Healthcheck

The image includes a native Docker `HEALTHCHECK` that pings Caddy's built-in admin API:

```
http://localhost:2019/config/
```

Docker Compose, Swarm, and orchestrators like Portainer will automatically detect container health and can restart it if the routing engine becomes unresponsive.

> ⚠️ **Important:** Do **not** set `admin off` in your Caddyfile, or the healthcheck will fail. The admin API only listens on `localhost` and is not exposed externally.

---

## 🚀 Quick Start

### 1. Create your project directory

```bash
mkdir caddy-sec && cd caddy-sec
```

### 2. Create a `compose.yml`

```yaml
services:
  caddy:
    image: dhimanparas20/caddy:latest
    container_name: custom-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./caddy_data:/data
      - ./caddy_config:/config
```

### 3. Create your `Caddyfile`

Copy the sample Caddyfile from this repo (see `Caddyfile.sample`) and customize it for your domain and backend:

```bash
cp Caddyfile.sample Caddyfile
```

### 4. Deploy

```bash
docker compose up -d
```

That's it. Caddy will automatically obtain and renew TLS certificates for your domain via Let's Encrypt.

---

## 🏗️ Architecture & Philosophy

The standard Caddy binary is phenomenal for automated HTTPS and easy routing, but it lacks native application-layer defense. **Caddy-Sec** implements a **Defense in Depth** architecture without sacrificing Caddy's signature performance.

### The Four Pillars

```
┌─────────────────────────────────────────────────────┐
│                   Incoming Request                   │
├──────────┬──────────┬──────────┬────────────────────┤
│  Pillar 1│  Pillar 2│  Pillar 3│      Pillar 4      │
│ CrowdSec │  Coraza  │   Rate   │    Healthcheck     │
│ IP Block │   WAF    │  Limit   │   (Self-Healing)   │
├──────────┴──────────┴──────────┴────────────────────┤
│              Caddy Reverse Proxy                     │
│           → your backend app:5050                    │
└─────────────────────────────────────────────────────┘
```

1. **Smart IP Bouncer (CrowdSec)** — Drops connections from known malicious IPs before they reach your app.
2. **Web Application Firewall (Coraza)** — Deep packet inspection blocks SQLi, XSS, and scanner fingerprints.
3. **Intelligent Rate Limiting** — Prevents brute-force and API spam with per-IP sliding windows.
4. **Native Self-Healing** — Docker-native healthcheck auto-restarts the container if Caddy hangs.

---

## 🔧 Configuration Guide

### Verify the Image

After starting the container, confirm all modules are loaded:

```bash
docker exec custom-caddy caddy list-modules | grep -E "coraza|crowdsec|rate"
```

Expected output:
```
http.handlers.crowdsec
http.handlers.coraza_waf
http.handlers.rate_limit
```

### Check Container Health

```bash
docker inspect --format='{{.State.Health.Status}}' custom-caddy
```

Expected output: `healthy`

### View Logs

```bash
docker logs -f custom-caddy
```

---

## 🔒 Security Best Practices

| Practice | Details |
|---|---|
| **Test WAF in detection mode first** | Set `SecRuleEngine DetectionOnly` in your Caddyfile before going to `On`. Check logs to ensure legitimate traffic isn't being blocked. |
| **Keep the image updated** | Periodically run `docker compose pull && docker compose up -d` to get the latest image with updated modules. |
| **Don't expose the admin API** | The admin API listens on `localhost:2019` by default. Never bind it to `0.0.0.0`. |
| **Use the default deny pattern** | End every site block with `handle { abort }` to silently drop unknown routes. |
| **Persist your data** | Always mount `/data` and `/config` as volumes to preserve TLS certificates across restarts. |

---

## 🔄 Updating

Since the image is pre-built on Docker Hub, updating is simple:

```bash
docker compose pull
docker compose up -d
```

No compilation. No waiting. The multi-arch manifest ensures you always get the right binary for your platform.

---

## 🖥️ Supported Platforms

| Architecture | Devices |
|---|---|
| `linux/amd64` | Cloud VPS, desktops, Intel/AMD servers |
| `linux/arm64` | Raspberry Pi 4/5, AWS Graviton, Apple Silicon (via Docker Desktop) |

---

## 📁 Repository Structure

```
.
├── Dockerfile           # Multi-stage build (for maintainers / custom builds)
├── compose.yml          # Production-ready Docker Compose stack
├── Caddyfile.sample     # Fully documented sample Caddyfile
└── README.md            # This file
```

---

## 📝 License

This project uses the [Caddy Web Server](https://caddyserver.com/) which is licensed under the Apache 2.0 License. All included modules are open source — see their respective repositories for license details.
