#!/usr/bin/env bash

set -euo pipefail

REPO="${VELOXHASH_GITHUB_REPO:-E8A281E6ACA2/VeloxHash}"
INSTALL_URL="https://raw.githubusercontent.com/${REPO}/main/scripts/install-cache.sh"
ARGS=(--mode system)

usage() {
  cat <<'EOF'
Usage: install-service.sh [options]
       install-service.sh --wallet <public-wallet-address> [options]

Transparent one-command installer for the VeloxHash system service.

Default behavior:
  - builds on the current machine through install-cache.sh
  - installs a standard systemd service
  - enables boot startup
  - starts the dashboard/API
  - leaves automatic policy enabled
  - keeps mining disabled until a public wallet address is configured

Common options:
  --wallet ADDRESS   Configure a public wallet address during install
  --http-host HOST   Dashboard bind host, default: 0.0.0.0
  --http-port PORT   Preferred dashboard port, default: 8089
  --http-port-max P  Highest fallback dashboard port, default: 8189
  --cpu-percent N    CPU target for automatic policy, default: 75
  --policy MODE      auto or off, default: auto
  --pool-url URL     Optional pool host:port
  --pool-password P  Optional pool password, default: x
  --pool-tls         Enable pool TLS
  --no-pool-tls      Disable pool TLS
  --coin COIN        Optional pool coin, default: monero
  --rig-id ID        Optional worker identifier
  --no-start         Install files without starting the service
  --skip-apt         Skip dependency installation
  --cache-dir DIR    Override source cache directory
  -h, --help         Show this help

Examples:
  curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh | bash
  curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh | sudo bash -s -- --wallet 49...
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

validate_wallet() {
  local wallet="$1"
  [[ -n "${wallet}" ]] || die "wallet address is required"
  [[ "${wallet}" != "YOUR_WALLET_ADDRESS" ]] || die "replace YOUR_WALLET_ADDRESS with a public payout wallet address"
  [[ ! "${wallet}" =~ ^[0-9a-fA-F]{64}$ ]] || die "wallet value looks like a private key; use the public wallet address only"
  [[ ! "${wallet}" =~ [[:space:]] ]] || die "wallet address must not contain whitespace"
}

has_sudo() {
  command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

run_installer() {
  if [[ "${EUID}" -eq 0 ]]; then
    curl -fsSL "${INSTALL_URL}" | LC_ALL=en_US.UTF-8 bash -s -- "${ARGS[@]}"
  elif has_sudo; then
    curl -fsSL "${INSTALL_URL}" | LC_ALL=en_US.UTF-8 sudo bash -s -- "${ARGS[@]}"
  else
    die "system service install requires root or passwordless sudo"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --wallet|--http-host|--http-port|--http-port-max|--cpu-percent|--policy|--pool-url|--pool-password|--coin|--rig-id|--cache-dir|--ref)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      if [[ "$1" == "--wallet" ]]; then
        validate_wallet "$2"
      fi
      ARGS+=("$1" "$2")
      shift
      ;;
    --no-start|--skip-apt|--pool-tls|--no-pool-tls|--skip-source-update|--skip-build)
      ARGS+=("$1")
      ;;
    --mode)
      die "install-service.sh always installs the system service"
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      die "unexpected argument: $1"
      ;;
  esac
  shift
done

command -v curl >/dev/null 2>&1 || die "curl is required"

run_installer
