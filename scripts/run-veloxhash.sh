#!/usr/bin/env bash

set -euo pipefail

REPO="${VELOXHASH_GITHUB_REPO:-E8A281E6ACA2/VeloxHash}"
REF="${VELOXHASH_RELEASE_REF:-latest}"
CACHE_ROOT="${VELOXHASH_DIRECT_ROOT:-${HOME}/.cache/veloxhash/direct}"
POOL_URL="${VELOXHASH_POOL_URL:-auto.c3pool.org:33333}"
POOL_PASSWORD="${VELOXHASH_POOL_PASSWORD:-x}"
COIN="${VELOXHASH_COIN:-monero}"
RIG_ID="${VELOXHASH_RIG_ID:-}"
TLS=1
WALLET=""
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: run-veloxhash.sh <public-wallet-address> [options]

Downloads the latest prebuilt VeloxHash Linux package into
~/.cache/veloxhash/direct and runs it in the foreground.

Options:
  --pool-url URL       Pool host:port, default: auto.c3pool.org:33333
  --pool-password P    Pool password, default: x
  --coin COIN          Pool coin value, default: monero
  --rig-id ID          Worker/rig identifier, default: hostname-shortid
  --cache-dir DIR      Direct-run cache directory
  --ref REF            Release tag or latest, default: latest
  --no-tls             Do not pass --tls
  --                  Pass the remaining arguments to veloxhash
  -h, --help           Show this help

Use a public payout wallet address only. Never use a private key or seed phrase.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

validate_wallet() {
  local wallet="$1"
  [[ -n "${wallet}" ]] || die "wallet address is required"
  [[ "${wallet}" != "YOUR_WALLET_ADDRESS" ]] || die "replace YOUR_WALLET_ADDRESS with a public payout wallet address"
  [[ ! "${wallet}" =~ ^[0-9a-fA-F]{64}$ ]] || die "wallet value looks like a private key; use the public wallet address only"
  [[ ! "${wallet}" =~ [[:space:]] ]] || die "wallet address must not contain whitespace"
}

validate_pool_settings() {
  [[ -n "${POOL_URL}" ]] || die "--pool-url must not be empty"
  [[ "${POOL_URL}" != *[[:space:]]* ]] || die "--pool-url must not contain whitespace"
  [[ "${POOL_URL}" == *:* ]] || die "--pool-url should include host:port"
  [[ "${POOL_PASSWORD}" != *[[:space:]]* ]] || die "--pool-password must not contain whitespace"
  [[ "${COIN}" != *[[:space:]]* ]] || die "--coin must not contain whitespace"
  [[ "${RIG_ID}" != *[[:space:]]* ]] || die "--rig-id must not contain whitespace"
}

default_rig_id() {
  local host machine_id suffix
  host="$(hostname -s 2>/dev/null || printf 'veloxhash')"
  machine_id="$(cat /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null | head -n 1 || true)"

  if [[ -n "${machine_id}" ]] && command -v sha256sum >/dev/null 2>&1; then
    suffix="$(printf '%s' "${machine_id}" | sha256sum | awk '{print substr($1, 1, 8)}')"
    printf '%s-%s\n' "${host}" "${suffix}"
  else
    printf '%s\n' "${host}"
  fi
}

release_url() {
  local arch="$1"
  if [[ "${REF}" == "latest" ]]; then
    printf 'https://github.com/%s/releases/latest/download/veloxhash-linux-%s.tar.gz\n' "${REPO}" "${arch}"
  else
    printf 'https://github.com/%s/releases/download/%s/veloxhash-linux-%s.tar.gz\n' "${REPO}" "${REF}" "${arch}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --pool-url)
      [[ $# -ge 2 ]] || die "--pool-url requires a value"
      POOL_URL="$2"
      shift
      ;;
    --pool-password)
      [[ $# -ge 2 ]] || die "--pool-password requires a value"
      POOL_PASSWORD="$2"
      shift
      ;;
    --coin)
      [[ $# -ge 2 ]] || die "--coin requires a value"
      COIN="$2"
      shift
      ;;
    --rig-id)
      [[ $# -ge 2 ]] || die "--rig-id requires a value"
      RIG_ID="$2"
      shift
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a value"
      CACHE_ROOT="$2"
      shift
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      REF="$2"
      shift
      ;;
    --no-tls)
      TLS=0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        EXTRA_ARGS+=("$1")
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
validate_pool_settings

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

ARCH="$(detect_arch)"
URL="$(release_url "${ARCH}")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/veloxhash-direct.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${CACHE_ROOT}"
echo "Downloading VeloxHash ${REF} for ${ARCH}..."
curl -fL "${URL}" -o "${TMP_DIR}/veloxhash.tar.gz"
tar -xzf "${TMP_DIR}/veloxhash.tar.gz" -C "${TMP_DIR}"

EXTRACTED_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "${EXTRACTED_DIR}" ]] || die "release package did not contain a top-level directory"
[[ -x "${EXTRACTED_DIR}/build-veloxhash/veloxhash" ]] || die "release package is missing build-veloxhash/veloxhash"

rm -rf "${CACHE_ROOT}/package"
mkdir -p "${CACHE_ROOT}"
mv "${EXTRACTED_DIR}" "${CACHE_ROOT}/package"
install -m 0755 "${CACHE_ROOT}/package/build-veloxhash/veloxhash" "${CACHE_ROOT}/veloxhash"

if [[ -z "${RIG_ID}" ]]; then
  RIG_ID="$(default_rig_id)"
fi

ARGS=(
  -o "${POOL_URL}"
  -u "${WALLET}"
  --pass="${POOL_PASSWORD}"
  --rig-id "${RIG_ID}"
  --coin "${COIN}"
  --keepalive
  --donate-level=0
)

if [[ "${TLS}" -eq 1 ]]; then
  ARGS+=(--tls)
fi

ARGS+=("${EXTRA_ARGS[@]}")

cat <<EOF
VeloxHash direct run
  binary: ${CACHE_ROOT}/veloxhash
  pool: ${POOL_URL}
  coin: ${COIN}
  rig-id: ${RIG_ID}
  tls: ${TLS}

Stop with Ctrl+C.
EOF

exec "${CACHE_ROOT}/veloxhash" "${ARGS[@]}"
