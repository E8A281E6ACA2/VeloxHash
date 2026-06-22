#!/usr/bin/env bash

set -euo pipefail

REPO="${VELOXHASH_GITHUB_REPO:-E8A281E6ACA2/VeloxHash}"
REF="${VELOXHASH_RELEASE_REF:-latest}"
CACHE_ROOT="${VELOXHASH_CACHE_ROOT:-${HOME}/.cache/veloxhash}"
SOURCE_DIR="${VELOXHASH_SOURCE_DIR:-${CACHE_ROOT}/source}"
TARBALL=""
ALLOW_BUILD_FALLBACK=1
INSTALL_ARGS=()
OS_ID="unknown"
OS_NAME="unknown"
PKG_MANAGER="none"

usage() {
  cat <<'EOF'
Usage: bash install-release.sh [public-wallet-address] [options]

Downloads a prebuilt VeloxHash Linux release package for the current CPU
architecture, extracts it into ~/.cache/veloxhash/source, then installs it.

One-line install:
  curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | sudo bash -s -- --mode system <public-wallet-address>

Options:
  --wallet ADDRESS      Public pool payout wallet address
  --mode MODE           auto, system, or user; default: auto
  --repo OWNER/REPO     GitHub repository, default: E8A281E6ACA2/VeloxHash
  --ref REF             Release tag or latest, default: latest
  --cache-dir DIR       Cache root, default: ~/.cache/veloxhash
  --http-host HOST      Dashboard/API bind host, default: 0.0.0.0
  --http-port PORT      Dashboard/API preferred port, default: 8089
  --http-port-max PORT  Highest fallback port, default: 8189
  --pool-url URL        Pool host:port, default: auto.c3pool.org:33333
  --pool-password P     Pool password, default: x
  --pool-tls            Enable pool TLS, default
  --no-pool-tls         Disable pool TLS
  --coin COIN           Pool coin value, default: monero
  --rig-id ID           Optional worker/rig identifier
  --cpu-percent N       CPU thread target, default: 75
  --policy MODE         auto or off; auto respects idle/work policy, off starts now
  --tarball URL         Download this tarball URL instead of querying GitHub
  --no-build-fallback   Fail if a matching release package is unavailable
  --no-start            Install files without starting VeloxHash
  --no-enable-boot      Do not configure boot startup for user-mode services
  -h, --help            Show this help

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

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
  else
    PKG_MANAGER="none"
  fi
}

has_sudo() {
  command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_runtime_deps() {
  if [[ "${EUID}" -ne 0 ]] && ! has_sudo; then
    echo "No root/sudo access; skipping automatic runtime dependency installation." >&2
    return
  fi

  case "${PKG_MANAGER}" in
    apt)
      run_as_root apt-get update
      packages=(ca-certificates curl tar python3 libuv1 libhwloc15)
      if apt-cache show libssl3t64 >/dev/null 2>&1; then
        packages+=(libssl3t64)
      else
        packages+=(libssl3)
      fi
      run_as_root apt-get install -y "${packages[@]}"
      ;;
    dnf)
      run_as_root dnf install -y ca-certificates curl tar python3 libuv hwloc openssl-libs
      ;;
    yum)
      run_as_root yum install -y ca-certificates curl tar python3 libuv hwloc openssl-libs
      ;;
    pacman)
      run_as_root pacman -Sy --needed --noconfirm ca-certificates curl tar python libuv hwloc openssl
      ;;
    apk)
      echo "Alpine/musl is not supported by the glibc prebuilt release package; source build fallback will be used if needed." >&2
      ;;
    *)
      echo "No supported package manager found; assuming runtime dependencies are already installed." >&2
      ;;
  esac
}

resolve_tarball_url() {
  local arch="$1"

  if [[ -n "${TARBALL}" ]]; then
    printf '%s\n' "${TARBALL}"
    return
  fi

  if [[ "${REF}" == "latest" ]]; then
    printf 'https://github.com/%s/releases/latest/download/veloxhash-linux-%s.tar.gz\n' "${REPO}" "${arch}"
  else
    printf 'https://github.com/%s/releases/download/%s/veloxhash-linux-%s.tar.gz\n' "${REPO}" "${REF}" "${arch}"
  fi
}

fallback_to_build() {
  if [[ "${ALLOW_BUILD_FALLBACK}" -ne 1 ]]; then
    die "no matching prebuilt release package found"
  fi

  echo "No matching prebuilt package found; falling back to source build." >&2
  curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/scripts/install-cache.sh" | bash -s -- --cache-dir "${CACHE_ROOT}" "${INSTALL_ARGS[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --wallet|--mode|--http-host|--http-port|--http-port-max|--pool-url|--pool-password|--coin|--rig-id|--cpu-percent|--policy)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      INSTALL_ARGS+=("$1" "$2")
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a value"
      REF="$2"
      shift
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a value"
      CACHE_ROOT="$2"
      SOURCE_DIR="${CACHE_ROOT}/source"
      shift
      ;;
    --tarball)
      [[ $# -ge 2 ]] || die "--tarball requires a value"
      TARBALL="$2"
      shift
      ;;
    --no-build-fallback)
      ALLOW_BUILD_FALLBACK=0
      ;;
    --no-start|--no-enable-boot|--pool-tls|--no-pool-tls)
      INSTALL_ARGS+=("$1")
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        INSTALL_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      INSTALL_ARGS+=("$1")
      ;;
  esac
  shift
done

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
detect_os
detect_pkg_manager
ARCH="$(detect_arch)"

URL="$(resolve_tarball_url "${ARCH}")"

cat <<EOF
VeloxHash install-release summary:
  system: ${OS_NAME}
  architecture: ${ARCH}
  package manager: ${PKG_MANAGER}
  cache: ${CACHE_ROOT}
  release: ${REF}
EOF

install_runtime_deps

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/veloxhash-release.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${CACHE_ROOT}"
if ! curl -fL "${URL}" -o "${TMP_DIR}/veloxhash.tar.gz"; then
  fallback_to_build
  exit 0
fi
tar -xzf "${TMP_DIR}/veloxhash.tar.gz" -C "${TMP_DIR}"

EXTRACTED_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "${EXTRACTED_DIR}" ]] || die "release package did not contain a top-level directory"
[[ -x "${EXTRACTED_DIR}/build-veloxhash/veloxhash" ]] || die "release package is missing build-veloxhash/veloxhash"
[[ -x "${EXTRACTED_DIR}/scripts/bootstrap-cache-install.sh" ]] || die "release package is missing scripts/bootstrap-cache-install.sh"

rm -rf "${SOURCE_DIR}"
mv "${EXTRACTED_DIR}" "${SOURCE_DIR}"

exec bash "${SOURCE_DIR}/scripts/bootstrap-cache-install.sh" --cache-dir "${CACHE_ROOT}" --skip-apt --skip-source-update --skip-build "${INSTALL_ARGS[@]}"
