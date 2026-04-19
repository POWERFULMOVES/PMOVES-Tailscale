#!/usr/bin/env bash
# Post-deployment validation for PMOVES Tailscale nodes.
# Checks: daemon running, backend state, connectivity to known peers.

set -euo pipefail

log() { printf '[tailscale-validate] %s\n' "$1"; }
warn() { printf '[tailscale-validate][warn] %s\n' "$1" >&2; }

ERRORS=0

# 1. Binary exists
if ! command -v tailscale >/dev/null 2>&1; then
  log "FAIL: tailscale binary not found"
  exit 1
fi
log "OK: tailscale binary found"

# 2. Backend state
STATUS_JSON=$(tailscale status --json 2>/dev/null || echo "{}")
BACKEND_STATE=$(printf '%s' "$STATUS_JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("BackendState", "Unknown"))
except:
    print("Unknown")
' 2>/dev/null || echo "Unknown")

if [[ "$BACKEND_STATE" == "Running" ]]; then
  log "OK: Backend state is Running"
else
  log "WARN: Backend state is $BACKEND_STATE"
  ERRORS=$((ERRORS + 1))
fi

# 3. Self IP
SELF_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [[ -n "$SELF_IP" ]]; then
  log "OK: Tailscale IPv4 = $SELF_IP"
else
  log "WARN: Could not determine Tailscale IPv4 address"
  ERRORS=$((ERRORS + 1))
fi

# 4. Known PMOVES peers
KNOWN_PEERS="${TAILSCALE_VALIDATE_PEERS:-}"
if [[ -n "$KNOWN_PEERS" ]]; then
  IFS=',' read -ra PEERS <<< "$KNOWN_PEERS"
  for peer in "${PEERS[@]}"; do
    peer=$(echo "$peer" | xargs)  # trim whitespace
    if tailscale ping --timeout=5s "$peer" >/dev/null 2>&1; then
      log "OK: Reachable peer: $peer"
    else
      log "WARN: Unreachable peer: $peer"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  log "SKIP: No TAILSCALE_VALIDATE_PEERS configured"
fi

# 5. Tailscale SSH (if expected)
if [[ "${TAILSCALE_SSH:-true}" == "true" ]]; then
  if tailscale status --json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
prefs = data.get("Prefs", data.get("prefs", {}))
print("true" if prefs.get("RunSSH", prefs.get("runSSH", False)) else "false")
' 2>/dev/null | grep -q "true"; then
    log "OK: Tailscale SSH is enabled"
  else
    log "WARN: Tailscale SSH does not appear enabled"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Summary
echo ""
if [[ $ERRORS -eq 0 ]]; then
  log "All checks passed."
else
  log "$ERRORS warning(s) detected. Review output above."
fi
exit 0
