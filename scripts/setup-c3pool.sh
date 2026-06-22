#!/usr/bin/env bash

set -euo pipefail

REPO="${VELOXHASH_GITHUB_REPO:-E8A281E6ACA2/VeloxHash}"
REF="${VELOXHASH_RELEASE_REF:-main}"
INSTALL_URL="https://raw.githubusercontent.com/${REPO}/main/scripts/install-cache.sh"
WALLET=""
ARGS=(--mode system --skip-apt --pool-url c3pool.org:33333 --pool-tls --policy off --cpu-percent 75)

usage() {
  cat <<'EOF'
Usage: setup-c3pool.sh <public-wallet-address> [options]

One-command system service installer. It downloads current VeloxHash source,
builds it locally on this machine, installs the systemd service, enables boot
startup, starts VeloxHash, and configures mining.

Defaults:
  mode: system
  pool-url: c3pool.org:33333
  pool-tls: enabled
  pool-password: x
  coin: monero
  policy: off
  cpu-percent: 75
  http-port: 8089, automatically falls forward if occupied

Options are passed through to install-cache.sh, including:
  --pool-url URL
  --pool-password P
  --pool-tls
  --no-pool-tls
  --coin COIN
  --rig-id ID
  --cpu-percent N
  --policy MODE
  --http-port PORT
  --ref REF
  -h, --help
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
    curl -fsSL "${INSTALL_URL}" | LC_ALL=en_US.UTF-8 bash -s -- "${ARGS[@]}" "${WALLET}"
  elif has_sudo; then
    curl -fsSL "${INSTALL_URL}" | LC_ALL=en_US.UTF-8 sudo bash -s -- "${ARGS[@]}" "${WALLET}"
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
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      REF="$2"
      ARGS+=("$1" "$2")
      shift
      ;;
    --pool-url|--pool-password|--coin|--rig-id|--cpu-percent|--policy|--http-host|--http-port|--http-port-max|--cache-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      ARGS+=("$1" "$2")
      shift
      ;;
    --no-start|--pool-tls|--no-pool-tls)
      ARGS+=("$1")
      ;;
    --mode)
      die "setup-c3pool.sh is system-service only"
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
      [[ -z "${WALLET}" ]] || die "wallet address was provided more than once"
      WALLET="$1"
      ;;
  esac
  shift
done

validate_wallet "${WALLET}"
command -v curl >/dev/null 2>&1 || die "curl is required"

run_installer
