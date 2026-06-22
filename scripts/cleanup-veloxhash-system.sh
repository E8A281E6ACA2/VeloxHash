#!/usr/bin/env bash

set -euo pipefail

UNINSTALL_URL="https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/uninstall-systemd-service.sh"

usage() {
  cat <<'EOF'
Usage: cleanup-veloxhash-system.sh [--purge] [--yes]

Downloads and runs the VeloxHash systemd uninstaller. By default it removes
installed commands and services while keeping config, logs, and backups.

Options:
  --purge   Remove config, state, logs, backups, and service user too
  --yes     Do not prompt for confirmation
  -h, --help
EOF
}

ARGS=()

has_sudo() {
  command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --purge|--yes|--no-backup)
      ARGS+=("$1")
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

if [[ "${EUID}" -eq 0 ]]; then
  curl -fsSL "${UNINSTALL_URL}" | bash -s -- "${ARGS[@]}"
elif has_sudo; then
  curl -fsSL "${UNINSTALL_URL}" | sudo bash -s -- "${ARGS[@]}"
else
  echo "error: system cleanup requires root or passwordless sudo" >&2
  exit 1
fi
