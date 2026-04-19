# PMOVES Tailscale Network Fabric

Deployment scripts, Headscale control plane, and Cloudflare integration for the PMOVES tailnet mesh.

## Quick Start

```bash
# Initialize submodule
git submodule update --init PMOVES-Tailscale

# Deploy on this host (workstation role, auto-detects platform)
bash PMOVES-Tailscale/deploy/deploy.sh

# Deploy with Headscale
TAILSCALE_AUTHKEY=<key> HEADSCALE_URL=https://headscale.pmoves.ai \
  bash PMOVES-Tailscale/deploy/deploy.sh --headscale

# Deploy as Docker subnet router (VPS)
bash PMOVES-Tailscale/deploy/deploy.sh --role vps --docker --headscale

# Windows
.\PMOVES-Tailscale\deploy\deploy.ps1

# Start Headscale control plane
make -C pmoves headscale-up
```

## Structure

```
deploy/              Universal deployment scripts
  deploy.sh          Linux/macOS/WSL provisioning
  deploy.ps1         Windows PowerShell provisioning
  lib/               Platform detection, install, validation
  profiles/          Per-role env defaults (workstation, vps, proxmox, edge)

headscale/           Self-hosted Tailscale control plane
  docker-compose.headscale.yml
  headscale.yaml     Config template
  acl.hujson         ACL policy

docker/              Docker-based Tailscale patterns
  docker-compose.tailscale-router.yml    Subnet router (VPS)
  docker-compose.tailscale-sidecar.yml   Per-service identity

cloudflare/          Cloudflare tunnel + DNS integration
  tunnel-config.yml.example
  setup.sh           Automated tunnel + DNS setup

pmoves-docs/         Extended documentation
  ARCHITECTURE.md    Network topology and diagrams
  HEADSCALE_SETUP.md Bootstrap guide
  CLOUDFLARE_INTEGRATION.md
  VPS_DEPLOYMENT.md  Hostinger-specific
  PROXMOX_DEPLOYMENT.md
  TROUBLESHOOTING.md
```

## Deployment Modes

| Target | Mode | Command |
|--------|------|---------|
| Workstation (Z890, 5090) | Host-level | `deploy.sh` or `deploy.ps1` |
| VPS (Hostinger) | Docker router | `deploy.sh --role vps --docker` |
| Proxmox | Host-level | `deploy.sh --role proxmox-host` |
| Edge (Nano, Pi) | Host-level | `deploy.sh --role edge` |
| Headscale | Docker Compose | `make -C pmoves headscale-up` |

## Current Tailnet Status

| Node | Status |
|------|--------|
| pmoves-z890 | Online |
| powerfulmoves (5090) | Offline (needs deploy) |
| pmoves-botz | Offline |
| pmoves-nano | Offline |
| pmoves-pro | Offline |

## Makefile Targets

From `pmoves/`:
```bash
make tailscale-deploy        # Host-level deploy
make tailscale-deploy-docker # Docker subnet router
make headscale-up            # Start Headscale
make headscale-down          # Stop Headscale
make headscale-create-user USER=pmoves
make headscale-create-key USER=pmoves
make tailscale-status        # Show tailscale status
```

## Documentation

- [Architecture](pmoves-docs/ARCHITECTURE.md) — Topology, ACLs, security model
- [Headscale Setup](pmoves-docs/HEADSCALE_SETUP.md) — Bootstrap guide
- [Cloudflare](pmoves-docs/CLOUDFLARE_INTEGRATION.md) — Domain mapping
- [VPS Deploy](pmoves-docs/VPS_DEPLOYMENT.md) — Hostinger-specific
- [Proxmox Deploy](pmoves-docs/PROXMOX_DEPLOYMENT.md) — Hypervisor setup
- [Troubleshooting](pmoves-docs/TROUBLESHOOTING.md) — Common issues and fixes
