# Troubleshooting Guide

## Common Issues

### Node won't join tailnet

**Check auth key:**
```bash
# Is the key valid?
docker exec pmoves-headscale headscale preauthkeys list --user pmoves
# Create a new one if expired
docker exec pmoves-headscale headscale preauthkeys create --user pmoves --reusable --expiration 90d
```

**Check login server URL:**
```bash
# Must be reachable
curl -s https://headscale.pmoves.ai/health
```

**Force re-auth:**
```bash
bash deploy/deploy.sh --force
# Or on Windows:
.\deploy.ps1 -Force
```

### Sentinel blocking re-deploy

The sentinel file prevents repeated joins. To override:
```bash
# Linux/macOS
rm ~/.config/pmoves/tailnet-initialized
# Windows
Remove-Item "$env:USERPROFILE\.config\pmoves\tailnet-initialized"
# Or use --force flag
```

### Tailscale status shows "NeedsLogin"

```bash
# Check if tailscaled is running
systemctl status tailscaled   # Linux
# Re-run deploy with auth key
TAILSCALE_AUTHKEY=<key> bash deploy/deploy.sh --force
```

### Docker router not connecting

```bash
# Check container logs
docker logs pmoves-tailscale --tail=50

# Common issues:
# - Missing TUN device: set TS_USERSPACE=true in .env
# - Missing capabilities: ensure cap_add: [NET_ADMIN, SYS_MODULE]
# - Network doesn't exist: docker network create pmoves_app
```

### Headscale health check failing

```bash
docker exec pmoves-headscale headscale health
docker logs pmoves-headscale --tail=30

# Check config syntax
docker exec pmoves-headscale cat /etc/headscale/config.yaml
```

### Nodes can't reach each other

```bash
# Check ACLs
docker exec pmoves-headscale headscale policy get

# Check routes
tailscale status
tailscale netcheck

# Direct connectivity test
tailscale ping <peer-hostname>
```

### Cloudflare tunnel not working

```bash
# Check tunnel status
cloudflared tunnel list
cloudflared tunnel info pmoves-tunnel

# Check DNS records
dig headscale.pmoves.ai

# Check cloudflared logs
docker logs cloudflared --tail=30
```

## Diagnostic Commands

```bash
# Full node status
tailscale status --json | python3 -m json.tool

# Network check (DERP servers, UDP, etc.)
tailscale netcheck

# Debug log
tailscale debug log

# Headscale nodes
docker exec pmoves-headscale headscale nodes list

# Headscale routes
docker exec pmoves-headscale headscale routes list
```

## Reset Everything

**Caution**: This removes the node from the tailnet.

```bash
# Leave tailnet
tailscale logout
tailscale down

# Remove sentinel
rm ~/.config/pmoves/tailnet-initialized

# Remove Headscale node entry (from control plane)
docker exec pmoves-headscale headscale nodes delete --identifier <NODE_ID>

# Re-deploy
bash deploy/deploy.sh --force
```
