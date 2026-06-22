#!/usr/bin/env bash

set -euo pipefail

CACHE_ROOT="${VELOXHASH_DIRECT_ROOT:-${HOME}/.cache/veloxhash/direct}"

usage() {
  cat <<'EOF'
Usage: cleanup-veloxhash-direct.sh [--yes] [--cache-dir DIR]

Stops direct-run VeloxHash processes from ~/.cache/veloxhash/direct and removes
the direct-run cache directory. It does not uninstall systemd/user services.

Options:
  --yes          Do not ask for confirmation
  --cache-dir DIR
                 Direct-run cache directory, default: ~/.cache/veloxhash/direct
  -h, --help     Show this help
EOF
}

ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --yes|-y)
      ASSUME_YES=1
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || { echo "error: --cache-dir requires a value" >&2; exit 1; }
      CACHE_ROOT="$2"
      shift
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  printf 'Remove VeloxHash direct-run cache at %s? [y/N] ' "${CACHE_ROOT}"
  read -r answer
  case "${answer}" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

if [[ -x "${CACHE_ROOT}/veloxhash" ]]; then
  pkill -f "${CACHE_ROOT}/veloxhash" 2>/dev/null || true
fi

rm -rf "${CACHE_ROOT}"
echo "VeloxHash direct-run cache removed: ${CACHE_ROOT}"
