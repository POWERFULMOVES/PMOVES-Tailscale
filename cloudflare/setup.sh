#!/usr/bin/env bash
# Cloudflare Tunnel + DNS setup for PMOVES services.
#
# Prerequisites:
#   - cloudflared CLI installed and authenticated
#   - CF_API_TOKEN or CF_API_KEY + CF_API_EMAIL set
#   - CLOUDFLARE_ZONE_ID set
#
# Usage:
#   setup.sh --tunnel-name pmoves-tunnel --domain pmoves.ai

set -euo pipefail

log()   { printf '[cf-setup] %s\n' "$1"; }
warn()  { printf '[cf-setup][warn] %s\n' "$1" >&2; }
fatal() { printf '[cf-setup][error] %s\n' "$1" >&2; exit 1; }

# ── CLI Args ────────────────────────────────────────────────────────────────

TUNNEL_NAME="${CF_TUNNEL_NAME:-pmoves-tunnel}"
DOMAIN="${CF_DOMAIN:-pmoves.ai}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tunnel-name) TUNNEL_NAME="$2"; shift 2 ;;
    --domain)      DOMAIN="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: setup.sh [--tunnel-name NAME] [--domain DOMAIN]"
      exit 0
      ;;
    *) fatal "Unknown arg: $1" ;;
  esac
done

# ── Verify Prerequisites ───────────────────────────────────────────────────

command -v cloudflared >/dev/null 2>&1 || fatal "cloudflared not found. Install: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"

# ── Create Tunnel ───────────────────────────────────────────────────────────

EXISTING_TUNNEL=$(cloudflared tunnel list --output json 2>/dev/null | \
  python3 - "$TUNNEL_NAME" <<'PYEOF'
import json, sys
tunnels = json.load(sys.stdin)
name = sys.argv[1]
for t in tunnels:
    if t.get('name') == name:
        print(t['id'])
        break
PYEOF
2>/dev/null || echo "")

if [[ -n "$EXISTING_TUNNEL" ]]; then
  log "Tunnel '$TUNNEL_NAME' already exists (ID: $EXISTING_TUNNEL)"
  TUNNEL_ID="$EXISTING_TUNNEL"
else
  log "Creating tunnel: $TUNNEL_NAME"
  TUNNEL_ID=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 | grep -oP '[a-f0-9-]{36}' | head -1)
  log "Created tunnel: $TUNNEL_ID"
fi

# ── Route DNS Records ──────────────────────────────────────────────────────

SUBDOMAINS=(
  "headscale"
  "headscale-ui"
  "api"
  "llm"
  "grafana"
  "rag"
)

for sub in "${SUBDOMAINS[@]}"; do
  FQDN="${sub}.${DOMAIN}"
  log "Routing DNS: $FQDN → tunnel $TUNNEL_NAME"
  cloudflared tunnel route dns "$TUNNEL_NAME" "$FQDN" 2>/dev/null || \
    warn "DNS route for $FQDN may already exist or failed."
done

# ── Summary ─────────────────────────────────────────────────────────────────

log ""
log "Tunnel setup complete."
log "  Tunnel Name: $TUNNEL_NAME"
log "  Tunnel ID:   $TUNNEL_ID"
log "  Domain:      $DOMAIN"
log ""
log "Next steps:"
log "  1. Copy tunnel-config.yml.example → tunnel-config.yml"
log "  2. Replace <TUNNEL_ID> with: $TUNNEL_ID"
log "  3. Run: cloudflared tunnel run $TUNNEL_NAME"
log "  4. Or add to Docker compose (see main repo cloudflare profile)"
