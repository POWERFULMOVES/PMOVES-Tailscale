# VPS Deployment Guide (Hostinger)

## Overview

The Hostinger VPS serves as:
1. **Headscale host** — always-on control plane for the tailnet
2. **Cloudflare tunnel endpoint** — public ingress for PMOVES services
3. **Optional service node** — lightweight services that benefit from always-on

## Prerequisites

- Hostinger VPS activated and accessible via SSH
- Ubuntu 22.04+ or Debian 12+ recommended
- Docker + Docker Compose installed
- This repo cloned with submodules

## Deploy Sequence

### 1. SSH into VPS

```bash
ssh root@<VPS_IP>
```

### 2. Clone Repository

```bash
git clone https://github.com/POWERFULMOVES/PMOVES.AI.git
cd PMOVES.AI
git submodule update --init PMOVES-Tailscale
```

### 3. Deploy Headscale

```bash
cd PMOVES-Tailscale/headscale
cp .env.example .env
# Edit .env: set HEADSCALE_URL=https://headscale.<your-domain>

docker compose -f docker-compose.headscale.yml up -d
```

### 4. Configure Cloudflare Tunnel

```bash
# Install cloudflared
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared

# Authenticate and create tunnel
cloudflared tunnel login
bash PMOVES-Tailscale/cloudflare/setup.sh --tunnel-name pmoves-tunnel --domain pmoves.ai
```

### 5. Deploy Tailscale Router (Docker mode)

```bash
cd PMOVES-Tailscale
# Create auth key first
docker exec pmoves-headscale headscale users create pmoves
TAILSCALE_AUTHKEY=$(docker exec pmoves-headscale headscale preauthkeys create \
  --user pmoves --reusable --expiration 90d 2>&1 | tail -1)

# Deploy router
TAILSCALE_AUTHKEY=$TAILSCALE_AUTHKEY \
HEADSCALE_URL=https://headscale.<domain> \
  bash deploy/deploy.sh --role vps --docker --headscale
```

### 6. Create Auth Keys for Other Nodes

```bash
# For workstations
docker exec pmoves-headscale headscale preauthkeys create \
  --user pmoves --reusable --expiration 90d
# Save this key for Z890, 5090, etc.
```

## Hardening

The existing VPS hardening script at `deploy/runners/vps/install-hardened.sh` covers:
- UFW firewall (allow 22, 80, 443, 41641/udp for WireGuard)
- fail2ban
- Unattended security updates
- SSH key-only auth

## Monitoring

Headscale exposes Prometheus metrics on port 9190:
```bash
curl http://localhost:9190/metrics
```

Add to your Prometheus scrape config to monitor the control plane.
