#!/usr/bin/env bash

set -euo pipefail

TARGET_URL="${VELOXHASH_SETUP_URL:-https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh}"

echo "setup-c3pool-one.sh is deprecated. Redirecting to install-service.sh." >&2
exec bash -c 'curl -fsSL "$0" | LC_ALL=en_US.UTF-8 bash -s -- "$@"' "${TARGET_URL}" "$@"
