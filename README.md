# 🛡️ Caddy-Sec: The Hardened Web Proxy

A custom, highly secure deployment of the [Caddy Web Server](https://caddyserver.com/), engineered for production environments. This repository provides a fully automated build system to compile Caddy with enterprise-grade security modules, transforming it from a standard reverse proxy into a robust Web Application Firewall (WAF) and automated bot-defense system.

Perfect for cloud VPS deployments or edge devices like a Raspberry Pi.

---

## 🏗️ Architecture & Philosophy

The standard Caddy binary is phenomenal for automated HTTPS and easy routing, but it lacks native application-layer defense. `Caddy-Sec` implements a **Defense in Depth** architecture without sacrificing Caddy's signature performance.

### The Four Pillars of Caddy-Sec

1. **Intelligent Rate Limiting** (`mholt/caddy-ratelimit`)
   * Prevents brute-force attacks and API spam by limiting requests per IP address across dynamic sliding windows.
2. **Web Application Firewall** (`corazawaf/coraza-caddy/v2`)
   * Deep packet inspection to block SQL Injections (SQLi), Cross-Site Scripting (XSS), and common vulnerability scanners (Nikto, Masscan) using OWASP Core Rule Sets.
3. **Smart IP Bouncer** (`hslatman/caddy-crowdsec-bouncer/http`)
   * Integrates with CrowdSec to automatically drop TCP connections from known malicious IP addresses, botnets, and DDoS nodes before they can even make an HTTP request.
4. **Native Self-Healing** (Baked-in Healthcheck)
   * A built-in Docker `HEALTHCHECK` using `wget` to continuously verify internal routing, meaning Docker Swarm or Compose can auto-restart the container if the routing engine hangs.

---

## 📂 Repository Structure

* `Dockerfile`: A multi-stage build script using `xcaddy` to compile the Go binary with the required security modules and inject the native healthcheck.
* `compose.yml`: A production-ready Docker Compose stack that builds the custom image and maps the necessary persistent volumes.
* `README.md`: Documentation and configuration guides.

---

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone [https://github.com/dhimanparas20/caddy-sec.git](https://github.com/dhimanparas20/caddy-sec.git)
cd caddy-sec
```

### 2. Create your Caddyfile
Create a `Caddyfile` in the same directory (or map it to `./server/Caddyfile` as defined in your compose setup). See the **Blueprint Caddyfile** section below for the required security syntax.

### 3. Build and Deploy
Let Docker Compose handle the compilation and deployment in one step:
```bash
docker compose up -d --build
```
*Note: The initial build will take a few minutes as it compiles the Go modules and the Coraza WAF engine from source.*

---

## 🛠️ The Blueprint Caddyfile

To utilize the compiled security modules and pass the native healthcheck, your `Caddyfile` must be configured correctly. Use this template as your baseline:

```caddyfile
# --- Global Options ---
{
    # Required: Initialize WAF before routing
    order coraza_waf first
    
    # Optional: Connect to local CrowdSec Engine
    # crowdsec {
    #     api_url http://crowdsec:8080
    #     api_key "YOUR_API_KEY"
    # }
}

example.com {
    # --- 1. WAF (Coraza) ---
    coraza_waf {
        directives `
            SecRuleEngine On
            SecRule REQUEST_HEADERS:User-Agent "@pm Nikto masscan zmap" "id:100,phase:1,deny,status:403,msg:'Scanner Blocked'"
            SecRule ARGS "@rx (?i)(union.*select|select.*from|insert.*into)" "id:101,phase:2,deny,status:403,msg:'SQLi Blocked'"
            SecRule ARGS "@rx (?i)(<script>|javascript:)" "id:102,phase:2,deny,status:403,msg:'XSS Blocked'"
        `
    }

    # --- 2. CrowdSec Bouncer ---
    # Uncomment if CrowdSec is configured globally
    # crowdsec

    # --- 3. Smart Rate Limiting ---
    # Protects dynamic routes but allows fast loading of static assets
    @not_static {
        not path /static*
    }
    rate_limit @not_static {
        zone default_zone {
            key {remote_host}
            events 20
            window 10s
        }
    }

    # --- 4. Internal Healthcheck (REQUIRED) ---
    # Fulfills the Dockerfile HEALTHCHECK ping
    handle /pingcaddy {
        respond "pong" 200
    }

    # --- 5. Application Routing ---
    # Whitelist your specific endpoints here
    @allowed_routes {
        path /api* /auth* /docs* /openapi.json*
    }
    handle @allowed_routes {
        reverse_proxy app:5050
    }

    # --- 6. Default Deny ---
    # Instantly drop unknown requests to save resources
    handle {
        abort
    }
}
```

---

## 🔒 Security Best Practices

* **Test the WAF first:** Before moving to production, change `SecRuleEngine On` to `SecRuleEngine DetectionOnly`. Check your Caddy logs to ensure legitimate traffic isn't being flagged by the Coraza rules before enforcing them.
* **Keep modules updated:** Periodically run `docker compose build --no-cache` to force `xcaddy` to pull the latest versions of the security modules from GitHub.
```
