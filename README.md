# Caddy-Sec: Hardened Caddy with WAF, CrowdSec, Rate Limit & Cache
A pre-built, production-oriented [Caddy](https://caddyserver.com/) image compiled with security and performance modules via
[xcaddy](https://github.com/caddyserver/xcaddy). Pull and deploy — no local Go build required.
**Docker Hub:** [hub.docker.com/r/dhimanparas20/caddy](https://hub.docker.com/r/dhimanparas20/caddy)
**Source:** [github.com/dhimanparas20/caddy-sec](https://github.com/dhimanparas20/caddy-sec)
```bash
docker pull dhimanparas20/caddy:latest
```
> Multi-arch: **linux/amd64** and **linux/arm64** (Raspberry Pi, Graviton, Apple Silicon). One `docker pull` selects the right digests.
---
## What's Inside
Built on official `caddy:latest`, with these modules compiled in:
| Module | Package | Purpose |
|--------|---------|---------|
| **Rate limit** | [mholt/caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | Per-IP / sliding-window request limiting |
| **WAF** | [corazawaf/coraza-caddy/v2](https://github.com/corazawaf/coraza-caddy) | Application-layer filtering (SQLi, XSS, scanners, custom rules) |
| **CrowdSec bouncer** | [hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer) | Reject decisions from a CrowdSec LAPI
(known bad IPs / bots) |
| **HTTP cache** | [caddyserver/cache-handler](https://github.com/caddyserver/cache-handler) | Reverse-proxy response cache (Souin-based) |
| **Otter storage** | [darkweak/storages/otter](https://github.com/darkweak/storages) | Fast **in-memory** cache backend for a single Caddy instance |
> Modules are **compiled into the binary**. Nothing is active until you enable it in your **Caddyfile** (and, for CrowdSec, run a CrowdSec engine).
### Dockerfile (what we build)
```dockerfile
xcaddy build \
  --with github.com/mholt/caddy-ratelimit@latest \
  --with github.com/hslatman/caddy-crowdsec-bouncer/http@latest \
  --with github.com/corazawaf/coraza-caddy/v2@latest \
  --with github.com/caddyserver/cache-handler \
  --with github.com/darkweak/storages/otter/caddy
```
---
## Architecture

                    Incoming HTTPS request
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
     CrowdSec            Coraza WAF          Rate limit
   (optional ban)      (payload rules)      (abuse throttle)
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ▼
                     HTTP cache (optional)
                     cache-handler + Otter
                              ▼
                      Reverse proxy / static
                              ▼
                         Your backends

| Layer | What it does | Needs extra config? |
|-------|----------------|---------------------|
| CrowdSec | Drop IPs already banned by CrowdSec | Yes — CrowdSec LAPI + API key |
| Coraza | Inspect request contents | Yes — `coraza_waf` directives / CRS |
| Rate limit | Cap request rate per key (usually IP) | Yes — `rate_limit` zones |
| Cache | Serve repeatable GET/HEAD responses from memory | Yes — global `cache` + per-route `cache` |
| Caddy core | TLS, routing, `reverse_proxy`, encode, etc. | Your site blocks |
**Otter** keeps cached bodies in process memory (fast, single-node). Cache is empty after container restart. For multi-Caddy / shared cache later,
swap in a Redis/Valkey storage module at build time.
---
## Quick Start
### 1. Project dir
```bash
mkdir caddy-sec && cd caddy-sec
```
### 2. `compose.yml`
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
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy_data:/data
      - ./caddy_config:/config
    # Admin API is localhost-only inside the container (do NOT use admin off
    # if you rely on this check).
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:2019/config/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
```
### 3. Caddyfile
```bash
cp Caddyfile.sample Caddyfile
# edit domain + upstream, then:
docker compose up -d
```
Caddy obtains and renews Let's Encrypt certificates automatically when DNS points at this host.
---
## Verify the image
```bash
docker exec custom-caddy caddy list-modules | grep -Ei 'rate_limit|coraza|crowdsec|cache|otter'
```
You should see modules similar to:
```text
http.handlers.rate_limit
http.handlers.coraza_waf
http.handlers.crowdsec
http.handlers.cache
...
```
Exact names can vary slightly by module version; absence of a name means that build did not include it.
```bash
docker inspect --format='{{.State.Health.Status}}' custom-caddy
docker logs -f custom-caddy
```
---
## Configuration notes
### Healthcheck / admin API
- Prefer a **Compose** `healthcheck` (as above). The image Dockerfile currently has the image-level `HEALTHCHECK` **commented out**.
- Healthchecks that hit `http://127.0.0.1:2019/config/` require the admin endpoint to stay enabled (default). **Do not set `admin off`** if you use
that probe.
- Never publish `:2019` to the host or bind admin to `0.0.0.0`.
### Rate limiting
Already demonstrated in `Caddyfile.sample`. Tune `events` / `window` per app; exclude static paths so assets are not throttled.
### Coraza (WAF)
- Start with `SecRuleEngine DetectionOnly`, watch logs, then switch to `On`.
- Sample rules in `Caddyfile.sample` are a **starting point**, not a full OWASP CRS install. For production CRS, mount rule files and point Coraza at
them.
- WAF adds CPU latency — enable where risk justifies it.
### CrowdSec
1. Run a CrowdSec instance (LAPI).
2. Create a bouncer API key.
3. Uncomment/configure the global `crowdsec { ... }` block and site `crowdsec` directive (see `Caddyfile.sample`).
Without a live LAPI, leave CrowdSec disabled in the Caddyfile (modules can still be present in the binary).
### HTTP cache (cache-handler + Otter)
**Capability is in the image; caching is off until you configure it.**
Minimal pattern:
```caddy
{
    cache {
        ttl 5m
        otter
    }
}

static.example.com {
      cache
      root * /srv
      file_server
}

Or cache only safe public GETs in front of a proxy:

cdn.example.com {
      @cacheable {
              method GET HEAD
      }
      cache @cacheable
      reverse_proxy app:8080
}

**Do cache:** public marketing pages, immutable static assets, clearly public cacheable APIs.
**Do not cache blindly:** authenticated apps, cookie/session responses, personalized HTML, WebSockets, admin UIs, anything with `Authorization` /
private `Set-Cookie`.
Wrong cache config can leak private responses between users. Prefer `Cache-Control` from the origin and short TTLs until you trust the setup. Inspect
`Cache-Status` response headers when debugging.
---
## Security best practices
| Practice | Detail |
|----------|--------|
| Detection mode first | Coraza `DetectionOnly` before `On` |
| Least privilege routes | Prefer allowlists + `handle { abort }` for unknown paths (see sample) |
| Persist TLS state | Always mount `/data` and `/config` |
| Keep image fresh | `docker compose pull && docker compose up -d` |
| Admin API private | Localhost only; never expose `:2019` |
| Cache with intent | Only on public, idempotent responses |
| CrowdSec optional | Don’t enable the directive without a working LAPI |
---
## Updating
```bash
docker compose pull
docker compose up -d
```
Multi-arch manifests mean the same tag works on amd64 and arm64.
---
## Rebuild from source (maintainers)
```bash
git clone https://github.com/dhimanparas20/caddy-sec.git
cd caddy-sec
docker buildx build --platform linux/amd64,linux/arm64 -t dhimanparas20/caddy:latest --push .
```
Requires BuildKit (for Go module cache mounts in the Dockerfile).
---
## Supported platforms
| Arch | Typical hosts |
|------|----------------|
| `linux/amd64` | Most VPS / bare metal |
| `linux/arm64` | Pi 4/5, Graviton, Apple Silicon (Docker Desktop) |
---
## Repository layout
```text
.
├── Dockerfile           # xcaddy multi-stage build
├── compose.yml          # Example Compose stack
├── Caddyfile.sample     # Documented starter Caddyfile
├── .github/             # CI / image publish workflows
└── README.md
```
---
## License
Caddy is Apache-2.0. Bundled modules are open source under their own licenses — see each upstream repository.
