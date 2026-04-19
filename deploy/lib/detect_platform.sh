#!/usr/bin/env bash
# Platform detection for PMOVES Tailscale deployment.
# Sources: OS, architecture, GPU availability.
# Usage: source this file, then use PMOVES_OS, PMOVES_ARCH, PMOVES_GPU variables.

set -euo pipefail

detect_os() {
  case "$(uname -s)" in
    Linux*)   PMOVES_OS="linux" ;;
    Darwin*)  PMOVES_OS="darwin" ;;
    CYGWIN*|MINGW*|MSYS*) PMOVES_OS="windows" ;;
    *)        PMOVES_OS="unknown" ;;
  esac
  export PMOVES_OS
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   PMOVES_ARCH="amd64" ;;
    aarch64|arm64)   PMOVES_ARCH="arm64" ;;
    armv7l|armhf)    PMOVES_ARCH="arm" ;;
    *)               PMOVES_ARCH="$(uname -m)" ;;
  esac
  export PMOVES_ARCH
}

detect_gpu() {
  PMOVES_GPU="none"
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
      PMOVES_GPU="nvidia"
    fi
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "apple"; then
      PMOVES_GPU="apple"
    fi
  fi
  export PMOVES_GPU
}

detect_init_system() {
  PMOVES_INIT="unknown"
  if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    PMOVES_INIT="systemd"
  elif command -v launchctl >/dev/null 2>&1; then
    PMOVES_INIT="launchd"
  elif [[ -f /etc/init.d/tailscaled ]]; then
    PMOVES_INIT="sysvinit"
  fi
  export PMOVES_INIT
}

detect_all() {
  detect_os
  detect_arch
  detect_gpu
  detect_init_system
}

# Auto-detect when sourced
detect_all
