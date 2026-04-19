#!/usr/bin/env bash
# Install Tailscale binary if not already present.
# Supports Linux (apt, yum, dnf, pacman, curl script), macOS (brew).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/detect_platform.sh"

log() { printf '[tailscale-install] %s\n' "$1"; }
warn() { printf '[tailscale-install][warn] %s\n' "$1" >&2; }
fatal() { printf '[tailscale-install][error] %s\n' "$1" >&2; exit 1; }

if command -v tailscale >/dev/null 2>&1; then
  CURRENT_VERSION=$(tailscale version 2>/dev/null | head -n1 || echo "unknown")
  log "Tailscale already installed: $CURRENT_VERSION"
  exit 0
fi

log "Installing Tailscale on ${PMOVES_OS}/${PMOVES_ARCH}..."

case "$PMOVES_OS" in
  linux)
    if command -v apt-get >/dev/null 2>&1; then
      log "Using apt package manager"
      curl -fsSL https://tailscale.com/install.sh | sh
    elif command -v dnf >/dev/null 2>&1; then
      log "Using dnf package manager"
      curl -fsSL https://tailscale.com/install.sh | sh
    elif command -v yum >/dev/null 2>&1; then
      log "Using yum package manager"
      curl -fsSL https://tailscale.com/install.sh | sh
    elif command -v pacman >/dev/null 2>&1; then
      log "Using pacman"
      sudo pacman -S --noconfirm tailscale
    else
      log "Using generic install script"
      curl -fsSL https://tailscale.com/install.sh | sh
    fi
    ;;
  darwin)
    if command -v brew >/dev/null 2>&1; then
      log "Using Homebrew"
      brew install tailscale
    else
      fatal "Homebrew not found. Install via: https://tailscale.com/download/mac"
    fi
    ;;
  windows)
    fatal "On Windows, install Tailscale from https://tailscale.com/download/windows or use deploy.ps1"
    ;;
  *)
    fatal "Unsupported OS: $PMOVES_OS"
    ;;
esac

# Verify installation
if command -v tailscale >/dev/null 2>&1; then
  log "Tailscale installed successfully: $(tailscale version 2>/dev/null | head -n1)"
else
  fatal "Tailscale installation failed — binary not found in PATH."
fi
