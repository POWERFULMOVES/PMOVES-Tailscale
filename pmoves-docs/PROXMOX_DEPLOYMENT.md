# Proxmox Deployment Guide

## Overview

On Proxmox, Tailscale is installed at the **hypervisor level**. This gives all VMs and LXC containers access to the tailnet via the host's Tailscale IP. Individual VMs can optionally have their own Tailscale identity.

## Prerequisites

- Proxmox VE 8.x+
- Headscale running and accessible (see `HEADSCALE_SETUP.md`)
- Pre-auth key from Headscale

## Install on Proxmox Host

### 1. Copy Deploy Script

```bash
scp -r PMOVES-Tailscale/deploy/ root@<PROXMOX_IP>:/opt/pmoves-tailscale/
```

### 2. Run Deploy

```bash
ssh root@<PROXMOX_IP>
cd /opt/pmoves-tailscale

TAILSCALE_AUTHKEY=<key> \
HEADSCALE_URL=https://headscale.pmoves.ai \
  bash deploy.sh --role proxmox-host --headscale
```

This will:
- Install Tailscale (if not present)
- Join the tailnet with `tag:pmoves,tag:proxmox`
- Advertise the Proxmox internal subnet (10.10.10.0/24)
- Enable Tailscale SSH

### 3. Verify

```bash
tailscale status
# Should show connected to Headscale with proxmox tags

# Test from another node
tailscale ping pmoves-proxmox
```

## VM/LXC with Individual Tailscale

For VMs that need their own tailnet identity:

```bash
# Inside the VM
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --login-server=https://headscale.pmoves.ai \
  --authkey=<key> \
  --hostname=pmoves-vm-<name> \
  --advertise-tags=tag:pmoves
```

## Subnet Routing

The Proxmox profile advertises `10.10.10.0/24` by default. Adjust `TAILSCALE_ADVERTISE_ROUTES` in the profile or env var to match your actual Proxmox network.

Other nodes must have `--accept-routes` to use these routes (enabled by default in all PMOVES profiles).

## Future: Migration from VPS

When Proxmox is fully operational, Headscale can be migrated:
1. Deploy Headscale on Proxmox (as VM or LXC)
2. Update Cloudflare tunnel to point to new IP
3. Re-key all nodes with new Headscale instance
4. Decommission VPS Headscale
