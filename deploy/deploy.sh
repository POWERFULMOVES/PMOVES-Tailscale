#!/usr/bin/env bash
#
# PMOVES Tailscale Deploy — Universal provisioning script.
#
# Idempotent. Provisions any PMOVES node onto the tailnet.
# Ported from: pmoves/scripts/tailscale_brand_init.sh + tailscale_brand_up.sh
#
# Usage:
#   deploy.sh [--role workstation|vps|proxmox-host|edge] [--headscale] [--docker] [--force]
#   deploy.sh --help

set -euo pipefail

# ── Logging ─────────────────────────────────────────────────────────────────

log()   { printf '[pmoves-tailscale] %s\n' "$1"; }
warn()  { printf '[pmoves-tailscale][warn] %s\n' "$1" >&2; }
fatal() { printf '[pmoves-tailscale][error] %s\n' "$1" >&2; exit 1; }

mask_key() {
  local key="$1" visible="${2:-4}"
  local length=${#key}
  [[ -z "$key" ]] && return
  if (( length <= visible )); then
    printf '%*s' "$length" '' | tr ' ' '*'
    return
  fi
  local prefix="${key:0:visible}"
  local mask; mask=$(printf '%*s' "$((length - visible))" '' | tr ' ' '*')
  printf '%s' "${prefix}${mask}"
}

# ── Paths ───────────────────────────────────────────────────────────────────

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"
PROFILES_DIR="$SCRIPT_DIR/profiles"

# ── CLI Argument Parsing ────────────────────────────────────────────────────

ROLE="${TAILSCALE_DEPLOY_ROLE:-workstation}"
USE_DOCKER="${TAILSCALE_DOCKER_MODE:-false}"
USE_HEADSCALE=false
FORCE=false

usage() {
  cat <<'USAGE'
PMOVES Tailscale Deploy

Usage: deploy.sh [OPTIONS]

Options:
  --role ROLE       Node role: workstation, vps, proxmox-host, edge (default: workstation)
  --docker          Deploy as Docker subnet router instead of host-level
  --headscale       Use Headscale login server (requires HEADSCALE_URL)
  --force           Force re-authentication even if sentinel exists
  --help            Show this help

Environment Variables:
  TAILSCALE_AUTHKEY              Auth key (or set TAILSCALE_AUTHKEY_FILE)
  TAILSCALE_AUTHKEY_FILE         Path to file containing auth key
  TAILSCALE_HOSTNAME             Hostname on tailnet (default: pmoves-$(hostname))
  TAILSCALE_TAGS                 Advertise tags (default: from profile)
  TAILSCALE_LOGIN_SERVER         Custom login server URL
  TAILSCALE_ADVERTISE_ROUTES     Subnet routes to advertise
  TAILSCALE_ACCEPT_ROUTES        Accept routes from peers (default: true)
  TAILSCALE_SSH                  Enable Tailscale SSH (default: true)
  TAILSCALE_SIGN_AUTHKEY         Lock signing mode: auto|false (default: auto)
  TAILSCALE_EXTRA_ARGS           Additional tailscale up arguments
  TAILSCALE_FORCE_REAUTH         Force re-auth (same as --force)
  TAILSCALE_VALIDATE_PEERS       Comma-separated peers to ping after join
  HEADSCALE_URL                  Headscale server URL
  TAILSCALE_DEPLOY_ROLE          Same as --role
  TAILSCALE_DOCKER_MODE          Same as --docker (true/false)

Examples:
  # Join tailnet as workstation (default)
  deploy.sh

  # Join via Headscale on VPS with Docker router
  deploy.sh --role vps --headscale --docker

  # Force re-auth on edge device
  deploy.sh --role edge --force
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)       ROLE="$2"; shift 2 ;;
    --docker)     USE_DOCKER=true; shift ;;
    --headscale)  USE_HEADSCALE=true; shift ;;
    --force)      FORCE=true; shift ;;
    --help|-h)    usage ;;
    *)            fatal "Unknown argument: $1. Use --help for usage." ;;
  esac
done

# ── Load Profile ────────────────────────────────────────────────────────────

PROFILE_FILE="$PROFILES_DIR/${ROLE}.env"
if [[ -f "$PROFILE_FILE" ]]; then
  log "Loading profile: $ROLE ($PROFILE_FILE)"
  set -a
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
  set +a
else
  warn "Profile $PROFILE_FILE not found; using environment variables only."
fi

# Allow env vars to override profile values (already exported above)
# Re-read CLI overrides that take precedence
[[ "$USE_DOCKER" == "true" ]] && TAILSCALE_DOCKER_MODE=true
[[ "$FORCE" == "true" ]] && TAILSCALE_FORCE_REAUTH=true

# ── Platform Detection ──────────────────────────────────────────────────────

source "$LIB_DIR/detect_platform.sh"
log "Platform: ${PMOVES_OS}/${PMOVES_ARCH} | GPU: ${PMOVES_GPU} | Init: ${PMOVES_INIT}"

# ── Docker Mode ─────────────────────────────────────────────────────────────

if [[ "${TAILSCALE_DOCKER_MODE:-false}" == "true" ]]; then
  log "Docker mode selected — deploying Tailscale subnet router container."

  DOCKER_DIR="$SCRIPT_DIR/../docker"
  COMPOSE_FILE="$DOCKER_DIR/docker-compose.tailscale-router.yml"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    fatal "Docker compose file not found: $COMPOSE_FILE"
  fi

  # Set Headscale login server if requested
  if [[ "$USE_HEADSCALE" == "true" ]]; then
    HEADSCALE_URL="${HEADSCALE_URL:-}"
    [[ -z "$HEADSCALE_URL" ]] && fatal "HEADSCALE_URL required when using --headscale"
    export HEADSCALE_URL
  fi

  docker compose -f "$COMPOSE_FILE" up -d
  log "Tailscale Docker router started. Waiting for healthy state..."

  for i in $(seq 1 30); do
    if docker exec pmoves-tailscale tailscale status >/dev/null 2>&1; then
      log "Tailscale Docker router is connected."
      docker exec pmoves-tailscale tailscale status
      exit 0
    fi
    sleep 2
  done

  warn "Tailscale Docker router did not become healthy within 60s."
  docker logs pmoves-tailscale --tail=20 2>&1
  exit 1
fi

# ── Host-Level Mode ─────────────────────────────────────────────────────────

log "Host-level deployment for role: $ROLE"

# Install if missing
if ! command -v tailscale >/dev/null 2>&1; then
  log "Tailscale not found — installing..."
  bash "$LIB_DIR/install_tailscale.sh"
fi

# ── Auth Key Resolution ─────────────────────────────────────────────────────

AUTH_KEY="${TAILSCALE_AUTHKEY:-}"
AUTH_KEY_FILE="${TAILSCALE_AUTHKEY_FILE:-}"

if [[ -z "$AUTH_KEY" && -n "$AUTH_KEY_FILE" && -f "$AUTH_KEY_FILE" ]]; then
  AUTH_KEY=$(tr -d '\r\n ' < "$AUTH_KEY_FILE")
  [[ -n "$AUTH_KEY" ]] && log "Loaded auth key from $AUTH_KEY_FILE"
fi

if [[ -z "$AUTH_KEY" ]]; then
  warn "No TAILSCALE_AUTHKEY or TAILSCALE_AUTHKEY_FILE found."
  warn "Continuing without auth key — interactive login will be required."
fi

# ── Tailnet Lock Signing ────────────────────────────────────────────────────

ORIGINAL_AUTH_KEY="$AUTH_KEY"
SIGN_MODE="${TAILSCALE_SIGN_AUTHKEY:-auto}"

if [[ -n "$AUTH_KEY" && "$SIGN_MODE" != "false" && "$SIGN_MODE" != "never" && "$SIGN_MODE" != "0" ]]; then
  log "Attempting Tailnet Lock signing (mode=$SIGN_MODE)."
  if SIGN_OUTPUT=$(tailscale lock sign "$AUTH_KEY" 2>&1); then
    NEW_KEY=$(printf '%s' "$SIGN_OUTPUT" | grep -o 'tskey-[A-Za-z0-9_-]\+' | tail -n1 || true)
    if [[ -n "$NEW_KEY" && "$NEW_KEY" != "$AUTH_KEY" ]]; then
      AUTH_KEY="$NEW_KEY"
      log "Signed auth key: $(mask_key "$AUTH_KEY")"
    else
      log "Lock sign succeeded but no new key emitted; using existing key."
    fi
  else
    warn "tailscale lock sign failed; continuing with original key."
  fi
fi

# Write back signed key if changed
if [[ "$AUTH_KEY" != "$ORIGINAL_AUTH_KEY" && -n "$AUTH_KEY_FILE" ]]; then
  mkdir -p "$(dirname "$AUTH_KEY_FILE")"
  printf '%s\n' "$AUTH_KEY" > "$AUTH_KEY_FILE"
  chmod 600 "$AUTH_KEY_FILE" 2>/dev/null || true
  log "Updated signed auth key at $AUTH_KEY_FILE"
fi

# ── Sentinel Check ──────────────────────────────────────────────────────────

SENTINEL_PATH="${TAILSCALE_INIT_SENTINEL:-$HOME/.config/pmoves/tailnet-initialized}"
FORCE_REAUTH="${TAILSCALE_FORCE_REAUTH:-false}"

if [[ -f "$SENTINEL_PATH" && "$FORCE_REAUTH" != "true" && "$FORCE_REAUTH" != "1" ]]; then
  log "Sentinel $SENTINEL_PATH found — already initialized."
  log "Use --force or TAILSCALE_FORCE_REAUTH=true to re-join."
  exit 0
fi

# ── Start tailscaled ────────────────────────────────────────────────────────

if [[ "$PMOVES_INIT" == "systemd" ]]; then
  if systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
      log "Starting tailscaled service..."
      if command -v sudo >/dev/null 2>&1; then
        sudo systemctl start tailscaled 2>/dev/null || warn "Failed to start tailscaled via sudo"
      else
        systemctl start tailscaled 2>/dev/null || warn "Failed to start tailscaled"
      fi
    fi
  fi
fi

# ── Build tailscale up Arguments ────────────────────────────────────────────

HOSTNAME="${TAILSCALE_HOSTNAME:-pmoves-$(hostname)}"
TAGS="${TAILSCALE_TAGS:-tag:pmoves}"
ROUTES="${TAILSCALE_ADVERTISE_ROUTES:-}"
LOGIN_SERVER="${TAILSCALE_LOGIN_SERVER:-}"
ACCEPT_ROUTES="${TAILSCALE_ACCEPT_ROUTES:-true}"
SSH="${TAILSCALE_SSH:-true}"
EXTRA_ARGS_RAW="${TAILSCALE_EXTRA_ARGS:-}"

# Use Headscale URL if --headscale flag or HEADSCALE_URL set
if [[ "$USE_HEADSCALE" == "true" || -n "${HEADSCALE_URL:-}" ]]; then
  LOGIN_SERVER="${HEADSCALE_URL:-$LOGIN_SERVER}"
  [[ -z "$LOGIN_SERVER" ]] && fatal "HEADSCALE_URL required when using --headscale"
fi

ARGS=(up)
[[ "$SSH" == "true" ]] && ARGS+=(--ssh)
[[ "$ACCEPT_ROUTES" == "true" ]] && ARGS+=(--accept-routes)
[[ -n "$TAGS" ]] && ARGS+=(--advertise-tags "$TAGS")
[[ -n "$ROUTES" ]] && ARGS+=(--advertise-routes "$ROUTES")
[[ -n "$HOSTNAME" ]] && ARGS+=(--hostname "$HOSTNAME")
[[ -n "$LOGIN_SERVER" ]] && ARGS+=(--login-server "$LOGIN_SERVER")
[[ "$FORCE_REAUTH" == "true" ]] && ARGS+=(--force-reauth)
[[ -n "$AUTH_KEY" ]] && ARGS+=(--auth-key "$AUTH_KEY")

if [[ -n "$EXTRA_ARGS_RAW" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARR=($EXTRA_ARGS_RAW)
  ARGS+=("${EXTRA_ARR[@]}")
fi

# ── Execute tailscale up ────────────────────────────────────────────────────

if [[ -n "$AUTH_KEY" ]]; then
  log "Executing: tailscale ${ARGS[*]//$AUTH_KEY/$(mask_key "$AUTH_KEY")}"
else
  log "Executing: tailscale ${ARGS[*]}"
  warn "No auth key — interactive login will follow."
fi

if tailscale "${ARGS[@]}"; then
  # Write sentinel
  mkdir -p "$(dirname "$SENTINEL_PATH")"
  date -u +'%Y-%m-%dT%H:%M:%SZ' > "$SENTINEL_PATH"
  chmod 600 "$SENTINEL_PATH" 2>/dev/null || true
  log "Tailscale up completed. Sentinel recorded at $SENTINEL_PATH"
else
  fatal "tailscale up failed."
fi

# ── Post-Deploy Validation ──────────────────────────────────────────────────

log "Running post-deploy validation..."
bash "$LIB_DIR/validate.sh" || true

# ── Summary ─────────────────────────────────────────────────────────────────

if STATUS_JSON=$(tailscale status --json 2>/dev/null); then
  BACKEND=$(printf '%s' "$STATUS_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("BackendState", "Unknown"))
except:
    print("Unknown")
' 2>/dev/null || echo "Unknown")
  SELF_IP=$(tailscale ip -4 2>/dev/null || echo "n/a")
  log "Backend: $BACKEND | IP: $SELF_IP | Hostname: $HOSTNAME | Role: $ROLE"
fi

log "Done."
