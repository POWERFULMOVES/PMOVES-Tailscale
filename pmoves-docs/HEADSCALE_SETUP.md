# Headscale Setup Guide

## Prerequisites

- Docker + Docker Compose on the target host (VPS or Proxmox)
- Cloudflare domain with tunnel configured (see `CLOUDFLARE_INTEGRATION.md`)
- This repo cloned with submodules: `git submodule update --init PMOVES-Tailscale`

## Quick Start

### 1. Configure Environment

```bash
cd PMOVES-Tailscale/headscale
cp .env.example .env
# Edit .env — set HEADSCALE_URL to your public URL
```

### 2. Start Headscale

```bash
docker compose -f docker-compose.headscale.yml up -d
```

Or from the main repo:
```bash
make -C pmoves headscale-up
```

### 3. Verify Health

```bash
docker exec pmoves-headscale headscale health
# Or:
curl http://localhost:8096/health
```

### 4. Create User + Auth Key

```bash
# Create the PMOVES user namespace
docker exec pmoves-headscale headscale users create pmoves

# Create a reusable pre-auth key (90-day expiry)
docker exec pmoves-headscale headscale preauthkeys create \
  --user pmoves --reusable --expiration 90d
```

Save the output key — this is your `TAILSCALE_AUTHKEY` for joining nodes.

### 5. Join Nodes to Headscale

On each node:
```bash
# Using the deploy script
TAILSCALE_AUTHKEY=<key> HEADSCALE_URL=https://headscale.pmoves.ai \
  bash PMOVES-Tailscale/deploy/deploy.sh --headscale

# Or manually
tailscale up --login-server=https://headscale.pmoves.ai --authkey=<key> \
  --hostname=pmoves-z890 --advertise-tags=tag:pmoves,tag:workstation --ssh
```

### 6. Verify Nodes

```bash
docker exec pmoves-headscale headscale nodes list
```

## ACL Policy Updates

Edit `acl.hujson` and restart Headscale:
```bash
docker compose -f docker-compose.headscale.yml restart headscale
```

## Backup

Headscale stores state in a SQLite database inside the `headscale-data` Docker volume.

```bash
# Backup
docker exec pmoves-headscale cp /var/lib/headscale/db.sqlite /tmp/headscale-backup.sqlite
docker cp pmoves-headscale:/tmp/headscale-backup.sqlite ./headscale-backup.sqlite

# Restore
docker cp headscale-backup.sqlite pmoves-headscale:/var/lib/headscale/db.sqlite
docker compose -f docker-compose.headscale.yml restart headscale
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Node can't connect | `docker exec pmoves-headscale headscale nodes list` — is the node registered? |
| Auth key rejected | Verify key hasn't expired: `headscale preauthkeys list --user pmoves` |
| DNS not resolving | Check `magic_dns: true` in headscale.yaml, verify `base_domain` |
| UI not loading | Check `HEADSCALE_URL` env var, verify tunnel routing |
