# Stage 1: Build the custom Caddy binary using xcaddy
FROM caddy:builder AS builder

# Compile Caddy with Rate Limiting, CrowdSec, and Coraza WAF
RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/corazawaf/coraza-caddy/v2

# Stage 2: Put the custom binary into the standard Caddy runtime image
FROM caddy:latest

# Copy the compiled binary from the builder stage
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Add the Healthcheck
# This uses wget (built into the Alpine base image) to hit your custom ping endpoint.
HEALTHCHECK --interval=2m --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/pingcaddy || exit 1
