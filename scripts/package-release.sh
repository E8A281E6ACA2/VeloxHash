#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${VELOXHASH_BUILD_DIR:-${ROOT_DIR}/build-veloxhash}"
DIST_DIR="${VELOXHASH_DIST_DIR:-${ROOT_DIR}/dist}"
VERSION="${VELOXHASH_VERSION:-}"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: ./scripts/package-release.sh [options]

Builds VeloxHash and creates a release tarball for the current Linux
architecture.

Options:
  --version VERSION  Version string used in the package directory name
  --skip-build       Package the existing build output
  -h, --help         Show this help

Output:
  dist/veloxhash-linux-amd64.tar.gz
  dist/veloxhash-linux-arm64.tar.gz
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      VERSION="$2"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  cmake -S . -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
  cmake --build "${BUILD_DIR}" -j"$(nproc)"
fi

BINARY="${BUILD_DIR}/veloxhash"
[[ -x "${BINARY}" ]] || die "missing build output: ${BINARY}"

ARCH="$(detect_arch)"
if [[ -z "${VERSION}" ]]; then
  VERSION="$("${BINARY}" --version 2>/dev/null | sed -n '1s/^VeloxHash //p')"
fi
[[ -n "${VERSION}" ]] || VERSION="dev"

PACKAGE_DIR="veloxhash-${VERSION}-linux-${ARCH}"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/veloxhash-package.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

install -d -m 0755 "${STAGE_DIR}/${PACKAGE_DIR}/build-veloxhash"
install -d -m 0755 "${STAGE_DIR}/${PACKAGE_DIR}/scripts" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/logrotate"
install -m 0755 "${BINARY}" "${STAGE_DIR}/${PACKAGE_DIR}/build-veloxhash/veloxhash"
install -m 0644 "${ROOT_DIR}/config-mining.json" "${STAGE_DIR}/${PACKAGE_DIR}/config-mining.json"

install -m 0755 "${ROOT_DIR}/scripts/bootstrap-cache-install.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/bootstrap-cache-install.sh"
install -m 0755 "${ROOT_DIR}/scripts/setup-veloxhash.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/setup-veloxhash.sh"
install -m 0755 "${ROOT_DIR}/scripts/cleanup-veloxhash-system.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/cleanup-veloxhash-system.sh"
install -m 0755 "${ROOT_DIR}/scripts/run-veloxhash.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/run-veloxhash.sh"
install -m 0755 "${ROOT_DIR}/scripts/cleanup-veloxhash-direct.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/cleanup-veloxhash-direct.sh"
install -m 0755 "${ROOT_DIR}/scripts/install-systemd-service.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/install-systemd-service.sh"
install -m 0755 "${ROOT_DIR}/scripts/uninstall-systemd-service.sh" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/uninstall-systemd-service.sh"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-mining" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-mining"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-policy" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-policy"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-cluster" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-cluster"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-doctor" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-doctor"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-status" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-status"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-validate" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-validate"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-backup" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-backup"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-restore" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-restore"
install -m 0755 "${ROOT_DIR}/scripts/veloxhash-upgrade" "${STAGE_DIR}/${PACKAGE_DIR}/scripts/veloxhash-upgrade"

install -m 0755 "${ROOT_DIR}/deploy/systemd/veloxhash-run" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-run"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash.service" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash.service"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash-policy.service" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-policy.service"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash-policy.timer" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-policy.timer"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash-cluster-primary.service" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-cluster-primary.service"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.service" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.service"
install -m 0644 "${ROOT_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.timer" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.timer"
install -m 0644 "${ROOT_DIR}/deploy/logrotate/veloxhash" "${STAGE_DIR}/${PACKAGE_DIR}/deploy/logrotate/veloxhash"

cat > "${STAGE_DIR}/${PACKAGE_DIR}/README.release" <<EOF
VeloxHash ${VERSION} Linux ${ARCH}

Install from this extracted package:
  sudo ./scripts/bootstrap-cache-install.sh --mode system --skip-apt --skip-source-update --skip-build <public-wallet-address>

Use a public payout wallet address only. Never use a private key or seed phrase.
EOF

mkdir -p "${DIST_DIR}"
tar -C "${STAGE_DIR}" -czf "${DIST_DIR}/veloxhash-linux-${ARCH}.tar.gz" "${PACKAGE_DIR}"
tar -C "${STAGE_DIR}" -czf "${DIST_DIR}/veloxhash-${VERSION}-linux-${ARCH}.tar.gz" "${PACKAGE_DIR}"
chmod 0644 "${DIST_DIR}/veloxhash-linux-${ARCH}.tar.gz" "${DIST_DIR}/veloxhash-${VERSION}-linux-${ARCH}.tar.gz"

cat <<EOF
Release packages created:
  ${DIST_DIR}/veloxhash-linux-${ARCH}.tar.gz
  ${DIST_DIR}/veloxhash-${VERSION}-linux-${ARCH}.tar.gz
EOF
