# Stage 1: Build the custom Caddy binary using xcaddy
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/corazawaf/coraza-caddy/v2

# Stage 2: Runtime
FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

## Healthcheck via Caddy's built-in admin API (plain HTTP, localhost only)
#HEALTHCHECK --interval=2m --timeout=5s --start-period=10s --retries=3 \
#    CMD wget --no-verbose --tries=1 --spider http://localhost:2019/config/ || exit 1
