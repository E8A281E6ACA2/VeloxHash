#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${VELOXHASH_REPO_URL:-https://github.com/E8A281E6ACA2/VeloxHash.git}"
REF="${VELOXHASH_REF:-main}"
CACHE_ROOT="${VELOXHASH_CACHE_ROOT:-${HOME}/.cache/veloxhash}"
SOURCE_DIR="${VELOXHASH_SOURCE_DIR:-${CACHE_ROOT}/source}"
DOWNLOAD_ONLY=0
BOOTSTRAP_ARGS=()

usage() {
  cat <<'EOF'
Usage: bash install-cache.sh [public-wallet-address] [options]

Downloads/updates VeloxHash into ~/.cache/veloxhash/source, then runs the
cache installer from that source tree.

Common one-line install:
  curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-cache.sh | bash -s -- <public-wallet-address>

System service install:
  curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-cache.sh | sudo bash -s -- --mode system <public-wallet-address>

Options:
  --wallet ADDRESS   Public pool payout wallet address
  --mode MODE        auto, system, or user; default: auto
  --repo URL         Git repository URL
  --ref REF          Git branch/tag/commit, default: main
  --cache-dir DIR    Cache root, default: ~/.cache/veloxhash
  --skip-apt         Do not install apt build dependencies
  --skip-build       Install existing build output from the cached source tree
  --no-start         Install files without starting VeloxHash
  --download-only    Only download/update the source tree, then exit
  -h, --help         Show this help

Use a public payout wallet address only. Never use a private key or seed phrase.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
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

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1 && { [[ "${EUID}" -eq 0 ]] || has_sudo; }; then
    run_as_root apt-get update
    run_as_root apt-get install -y ca-certificates git
    return
  fi

  die "git is required. Install git first, or rerun as root/sudo on Ubuntu/Debian."
}

refresh_source() {
  mkdir -p "${CACHE_ROOT}"

  if [[ -e "${SOURCE_DIR}" && ! -d "${SOURCE_DIR}/.git" ]]; then
    die "${SOURCE_DIR} already exists but is not a Git checkout"
  fi

  if [[ -d "${SOURCE_DIR}/.git" ]]; then
    current_remote="$(git -C "${SOURCE_DIR}" remote get-url origin 2>/dev/null || true)"
    if [[ "${current_remote}" != "${REPO_URL}" ]]; then
      git -C "${SOURCE_DIR}" remote set-url origin "${REPO_URL}"
    fi
    git -C "${SOURCE_DIR}" fetch --prune origin
  else
    git clone "${REPO_URL}" "${SOURCE_DIR}"
  fi

  git -C "${SOURCE_DIR}" checkout "${REF}"
  git -C "${SOURCE_DIR}" pull --ff-only origin "${REF}" 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --wallet|--mode)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      BOOTSTRAP_ARGS+=("$1" "$2")
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO_URL="$2"
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
    --skip-apt|--skip-build|--no-start)
      BOOTSTRAP_ARGS+=("$1")
      ;;
    --download-only)
      DOWNLOAD_ONLY=1
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        BOOTSTRAP_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      BOOTSTRAP_ARGS+=("$1")
      ;;
  esac
  shift
done

ensure_git
refresh_source

if [[ "${DOWNLOAD_ONLY}" -eq 1 ]]; then
  cat <<EOF
VeloxHash source is ready:
  ${SOURCE_DIR}

Run installer:
  bash ${SOURCE_DIR}/scripts/bootstrap-cache-install.sh <public-wallet-address>
EOF
  exit 0
fi

INSTALLER="${SOURCE_DIR}/scripts/bootstrap-cache-install.sh"
[[ -f "${INSTALLER}" ]] || die "missing installer: ${INSTALLER}"

export VELOXHASH_REPO_URL="${REPO_URL}"
export VELOXHASH_REF="${REF}"
export VELOXHASH_CACHE_ROOT="${CACHE_ROOT}"
export VELOXHASH_SOURCE_DIR="${SOURCE_DIR}"

exec bash "${INSTALLER}" "${BOOTSTRAP_ARGS[@]}"
