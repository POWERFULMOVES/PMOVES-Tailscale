# Cloudflare Integration Guide

## Overview

Cloudflare provides:
1. **DNS** — public domain resolution for PMOVES services
2. **Tunnels** — secure ingress from internet to internal services (no port exposure)
3. **TLS** — edge TLS termination (free Universal SSL)

## Prerequisites

- Cloudflare account with domain(s) added
- `cloudflared` CLI installed: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
- Domain nameservers pointed to Cloudflare

## Setup

### 1. Authenticate cloudflared

```bash
cloudflared tunnel login
```

### 2. Run Automated Setup

```bash
bash PMOVES-Tailscale/cloudflare/setup.sh --tunnel-name pmoves-tunnel --domain pmoves.ai
```

This creates the tunnel and DNS CNAME records for all configured subdomains.

### 3. Configure Tunnel Routes

```bash
cp cloudflare/tunnel-config.yml.example cloudflare/tunnel-config.yml
# Edit: replace <TUNNEL_ID> with actual ID from step 2
```

### 4. Run the Tunnel

Via Docker (recommended — add to your compose):
```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run
    volumes:
      - ./cloudflare/tunnel-config.yml:/etc/cloudflared/config.yml:ro
      - cloudflared-creds:/etc/cloudflared
    restart: unless-stopped
```

Or standalone:
```bash
cloudflared tunnel --config cloudflare/tunnel-config.yml run
```

## Domain Mapping

See `cloudflare/dns-records.md` for the full inventory.

Key routes:
| Subdomain | Internal Service |
|-----------|-----------------|
| `headscale.pmoves.ai` | Headscale control plane (8096) |
| `api.pmoves.ai` | Agent Zero (8080) |
| `llm.pmoves.ai` | TensorZero Gateway (3030) |
| `grafana.pmoves.ai` | Grafana (3000) |
| `rag.pmoves.ai` | Hi-RAG v2 (8086) |

## Security Notes

- Tunnel traffic is encrypted end-to-end (Cloudflare edge → `cloudflared` agent)
- Internal services do NOT need TLS — Cloudflare handles it
- Use Cloudflare Access policies for authentication on sensitive endpoints
- Never expose Headscale directly to the internet without the tunnel
