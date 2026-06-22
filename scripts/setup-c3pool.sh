#!/usr/bin/env bash

set -euo pipefail

ROOT_URL="${VELOXHASH_SETUP_URL:-https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/setup-veloxhash.sh}"

exec bash -c 'curl -fsSL "$0" | LC_ALL=en_US.UTF-8 bash -s -- "$@"' "${ROOT_URL}" "$@"
