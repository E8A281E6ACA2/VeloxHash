#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLET="${VELOXHASH_WALLET_ADDRESS:-}"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: sudo ./start-mining.sh [public-wallet-address] [--skip-build]

Builds VeloxHash from this source tree, installs the physical-host systemd
service, and optionally configures the public pool payout wallet address.

Examples:
  sudo ./start-mining.sh
  sudo ./start-mining.sh 49...
  sudo VELOXHASH_WALLET_ADDRESS=49... ./start-mining.sh --skip-build

Notes:
  Use a public payout wallet address only. Never use a private key or seed phrase.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

validate_public_wallet() {
  local wallet="$1"

  [[ -n "${wallet}" ]] || return 0
  [[ "${wallet}" != "YOUR_WALLET_ADDRESS" ]] || die "replace YOUR_WALLET_ADDRESS with a public payout wallet address"

  if [[ "${wallet}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    die "wallet value looks like a private key; use the public wallet address only"
  fi

  if [[ "${wallet}" =~ [[:space:]] ]]; then
    die "wallet address must not contain whitespace"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --wallet)
      [[ $# -ge 2 ]] || die "--wallet requires a value"
      WALLET="$2"
      shift
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "${WALLET}" || "${WALLET}" == "${1}" ]] || die "wallet address was provided more than once"
      WALLET="$1"
      ;;
  esac
  shift
done

if [[ "${EUID}" -ne 0 ]]; then
  die "run with sudo so the systemd service can be installed"
fi

validate_public_wallet "${WALLET}"

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  cmake -S . -B build-veloxhash -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
  cmake --build build-veloxhash -j"$(nproc)"
fi

"${ROOT_DIR}/scripts/install-systemd-service.sh" --enable --start

if [[ -n "${WALLET}" ]]; then
  /usr/local/bin/veloxhash-mining wallet set "${WALLET}"
fi

cat <<'EOF'

VeloxHash physical-host service is installed.

Dashboard:
  http://<server-ip>:8089/

Useful commands:
  sudo veloxhash-mining token
  sudo veloxhash-mining status
  sudo veloxhash-policy status
  sudo veloxhash-status --short
  sudo veloxhash-doctor
EOF
