#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/veloxhash-entry-test.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

BIN_DIR="${TMP_DIR}/bin"
LOG_FILE="${TMP_DIR}/entry.log"
mkdir -p "${BIN_DIR}"

cat > "${BIN_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl_args=%s\n' "$*" >> "${VELOXHASH_TEST_LOG}"
cat <<'SCRIPT'
#!/usr/bin/env bash
printf 'installer_argv=' >> "${VELOXHASH_TEST_LOG}"
printf '%q ' "$@" >> "${VELOXHASH_TEST_LOG}"
printf '\n' >> "${VELOXHASH_TEST_LOG}"
SCRIPT
EOF
chmod 0755 "${BIN_DIR}/curl"

cat > "${BIN_DIR}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo_argv=' >> "${VELOXHASH_TEST_LOG}"
printf '%q ' "$@" >> "${VELOXHASH_TEST_LOG}"
printf '\n' >> "${VELOXHASH_TEST_LOG}"
exec "$@"
EOF
chmod 0755 "${BIN_DIR}/sudo"

WALLET="494W5RU4evwbxM9392BVMG71wTk1mhrZ3iy9q3Civc4PJcift2yyBp6Bnx82mLJTkvfS6AS5MjJV8TDTU6NGLjwwKZ9Fth5"
export VELOXHASH_TEST_LOG="${LOG_FILE}"

PATH="${BIN_DIR}:$PATH" bash "${ROOT_DIR}/scripts/setup-c3pool-one.sh" "${WALLET}" --pool-url test.pool:3333 --cpu-percent 60 --policy off >/dev/null 2>&1 || true

cat "${LOG_FILE}"
