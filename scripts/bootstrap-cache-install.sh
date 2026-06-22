#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${VELOXHASH_REPO_URL:-https://github.com/E8A281E6ACA2/VeloxHash.git}"
REF="${VELOXHASH_REF:-main}"
CACHE_ROOT="${VELOXHASH_CACHE_ROOT:-${HOME}/.cache/veloxhash}"
SOURCE_DIR="${VELOXHASH_SOURCE_DIR:-${CACHE_ROOT}/source}"
USER_PREFIX="${VELOXHASH_USER_PREFIX:-${CACHE_ROOT}/runtime}"
USER_BIN="${USER_PREFIX}/bin/veloxhash"
USER_CONFIG_DIR="${USER_PREFIX}/config"
USER_STATE_DIR="${USER_PREFIX}/state"
USER_LOG_DIR="${USER_PREFIX}/logs"
USER_RUNNER="${USER_PREFIX}/bin/veloxhash-run"
USER_CTL="${USER_PREFIX}/bin/veloxhash-user"
USER_ENV_FILE="${USER_CONFIG_DIR}/veloxhash.env"
USER_CONFIG_FILE="${USER_CONFIG_DIR}/config.json"
USER_SERVICE_DIR="${HOME}/.config/systemd/user"
USER_SERVICE_FILE="${USER_SERVICE_DIR}/veloxhash.service"
WALLET="${VELOXHASH_WALLET_ADDRESS:-}"
POOL_URL="${VELOXHASH_POOL_URL:-auto.c3pool.org:33333}"
POOL_PASSWORD="${VELOXHASH_POOL_PASSWORD:-x}"
POOL_TLS="${VELOXHASH_POOL_TLS:-1}"
COIN="${VELOXHASH_COIN:-monero}"
RIG_ID="${VELOXHASH_RIG_ID:-}"
MODE="${VELOXHASH_INSTALL_MODE:-auto}"
SKIP_APT=0
SKIP_BUILD=0
SKIP_SOURCE_UPDATE=0
START_SERVICE=1
ENABLE_BOOT=1
POLICY_MODE="${VELOXHASH_POLICY_MODE:-auto}"
CPU_PERCENT="${VELOXHASH_POLICY_CPU_PERCENT:-75}"
HTTP_HOST="${VELOXHASH_HTTP_HOST:-0.0.0.0}"
HTTP_PORT="${VELOXHASH_HTTP_PORT:-8089}"
HTTP_PORT_MAX="${VELOXHASH_HTTP_PORT_MAX:-8189}"
OS_ID="unknown"
OS_NAME="unknown"
ARCH="unknown"
PKG_MANAGER="none"

usage() {
  cat <<'EOF'
Usage: bash bootstrap-cache-install.sh [public-wallet-address] [options]

Downloads/updates VeloxHash source under ~/.cache/veloxhash/source and builds
it for the current host architecture unless --skip-build is used.

Modes:
  auto    root -> system service, non-root -> user service/background process
  system  install systemd service under /etc and /usr/local/bin
  user    install into ~/.cache/veloxhash/runtime and run as the current user

Options:
  --wallet ADDRESS   Public pool payout wallet address
  --mode MODE        auto, system, or user; default: auto
  --repo URL         Git repository URL
  --ref REF          Git branch/tag/commit, default: main
  --cache-dir DIR    Cache root, default: ~/.cache/veloxhash
  --http-host HOST   Dashboard/API bind host, default: 0.0.0.0
  --http-port PORT   Dashboard/API preferred port, default: 8089
  --http-port-max PORT
                    Highest fallback port, default: 8189
  --pool-url URL     Pool host:port, default: auto.c3pool.org:33333
  --pool-password P  Pool password, default: x
  --pool-tls         Enable pool TLS, default
  --no-pool-tls      Disable pool TLS
  --coin COIN        Pool coin value, default: monero
  --rig-id ID        Optional worker/rig identifier
  --cpu-percent N    CPU thread target, default: 75
  --policy MODE      auto or off; auto respects idle/work policy, off starts now
  --skip-apt         Do not install apt build dependencies
  --skip-source-update
                     Use the existing cached/extracted source tree as-is
  --skip-build       Install existing build output from the cached source tree
  --no-start         Install files without starting VeloxHash
  --no-enable-boot   Do not configure boot startup for user-mode services
  -h, --help         Show this help

Examples:
  bash bootstrap-cache-install.sh 49...
  bash bootstrap-cache-install.sh --mode user 49...
  sudo bash bootstrap-cache-install.sh --mode system 49...

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

validate_pool_settings() {
  [[ -n "${POOL_URL}" ]] || die "--pool-url must not be empty"
  [[ "${POOL_URL}" != *[[:space:]]* ]] || die "--pool-url must not contain whitespace"
  [[ "${POOL_URL}" == *:* ]] || die "--pool-url should include host:port"
  [[ "${POOL_PASSWORD}" != *[[:space:]]* ]] || die "--pool-password must not contain whitespace"
  case "${POOL_TLS}" in
    1|true|TRUE|yes|YES|on|ON|0|false|FALSE|no|NO|off|OFF) ;;
    *) die "pool TLS value must be on/off" ;;
  esac
  [[ "${COIN}" != *[[:space:]]* ]] || die "--coin must not contain whitespace"
  [[ "${RIG_ID}" != *[[:space:]]* ]] || die "--rig-id must not contain whitespace"
  [[ "${CPU_PERCENT}" =~ ^[0-9]+$ ]] || die "--cpu-percent must be a number"
  (( CPU_PERCENT >= 1 && CPU_PERCENT <= 100 )) || die "--cpu-percent must be between 1 and 100"
  case "${POLICY_MODE}" in
    auto|off) ;;
    *) die "--policy must be auto or off" ;;
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

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
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

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
    return
  fi

  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
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

enable_user_linger_if_possible() {
  local user="$1"

  [[ "${ENABLE_BOOT}" -eq 1 ]] || return 1
  command -v loginctl >/dev/null 2>&1 || return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  [[ -d /run/systemd/system ]] || return 1

  if [[ "${EUID}" -eq 0 ]]; then
    loginctl enable-linger "${user}" >/dev/null 2>&1 && return 0
  elif has_sudo; then
    sudo loginctl enable-linger "${user}" >/dev/null 2>&1 && return 0
  fi

  return 1
}

port_owner_is_veloxhash() {
  local port="$1"
  ss -ltnp 2>/dev/null | awk -v port=":${port}" '$4 ~ port "$" {print}' | grep -q 'veloxhash'
}

port_is_listening() {
  local port="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
}

select_http_port() {
  local start="$1"
  local max="$2"
  local port

  [[ "${start}" =~ ^[0-9]+$ ]] || die "--http-port must be a number"
  [[ "${max}" =~ ^[0-9]+$ ]] || die "--http-port-max must be a number"
  (( start >= 1 && start <= 65535 )) || die "--http-port must be between 1 and 65535"
  (( max >= 1 && max <= 65535 )) || die "--http-port-max must be between 1 and 65535"
  (( start <= max )) || die "--http-port must be less than or equal to --http-port-max"

  if ! command -v ss >/dev/null 2>&1; then
    printf '%s\n' "${start}"
    return
  fi

  for ((port=start; port<=max; port++)); do
    if ! port_is_listening "${port}" || port_owner_is_veloxhash "${port}"; then
      printf '%s\n' "${port}"
      return
    fi
  done

  die "no free HTTP port found in ${start}-${max}"
}

update_source() {
  mkdir -p "${CACHE_ROOT}"

  if [[ -d "${SOURCE_DIR}/.git" ]]; then
    git -C "${SOURCE_DIR}" fetch --prune origin
  else
    rm -rf "${SOURCE_DIR}"
    git clone "${REPO_URL}" "${SOURCE_DIR}"
  fi

  git -C "${SOURCE_DIR}" checkout "${REF}"
  git -C "${SOURCE_DIR}" pull --ff-only origin "${REF}" 2>/dev/null || true
}

build_source() {
  if [[ "${SKIP_BUILD}" -eq 0 ]]; then
    cmake -S "${SOURCE_DIR}" -B "${SOURCE_DIR}/build-veloxhash" -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
    cmake --build "${SOURCE_DIR}/build-veloxhash" -j"$(nproc)"
  fi

  [[ -x "${SOURCE_DIR}/build-veloxhash/veloxhash" ]] || die "missing build output: ${SOURCE_DIR}/build-veloxhash/veloxhash"
}

install_deps_if_allowed() {
  if [[ "${SKIP_APT}" -eq 1 ]]; then
    return
  fi

  if [[ "${EUID}" -eq 0 ]] || has_sudo; then
    case "${PKG_MANAGER}" in
      apt)
        run_as_root apt-get update
        run_as_root apt-get install -y build-essential ca-certificates cmake curl git python3 libuv1-dev libssl-dev libhwloc-dev
        return
        ;;
      dnf)
        run_as_root dnf groupinstall -y "Development Tools" || true
        run_as_root dnf install -y ca-certificates cmake curl git python3 libuv-devel openssl-devel hwloc-devel
        return
        ;;
      yum)
        run_as_root yum groupinstall -y "Development Tools" || true
        run_as_root yum install -y ca-certificates cmake curl git python3 libuv-devel openssl-devel hwloc-devel
        return
        ;;
      pacman)
        run_as_root pacman -Sy --needed --noconfirm base-devel ca-certificates cmake curl git python libuv openssl hwloc
        return
        ;;
      apk)
        echo "Alpine/musl build support is experimental; installing best-effort build dependencies." >&2
        run_as_root apk add --no-cache build-base ca-certificates cmake curl git python3 libuv-dev openssl-dev hwloc-dev
        return
        ;;
      *)
        echo "No supported package manager found; checking existing build tools." >&2
        ;;
    esac
  fi

  for cmd in git cmake python3; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} is required. Install dependencies or rerun with sudo/root."
  done
}

write_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
line = f"{key}={value}"
lines = path.read_text().splitlines() if path.exists() else []
out = []
updated = False
for item in lines:
    if item.startswith(f"{key}="):
        out.append(line)
        updated = True
    else:
        out.append(item)
if not updated:
    out.append(line)
path.write_text("\n".join(out) + "\n")
PY
}

write_system_env_value() {
  local key="$1"
  local value="$2"
  run_as_root python3 - "/etc/veloxhash/veloxhash.env" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
line = f"{key}={value}"
lines = path.read_text().splitlines() if path.exists() else []
out = []
updated = False
for item in lines:
    if item.startswith(f"{key}="):
        out.append(line)
        updated = True
    else:
        out.append(item)
if not updated:
    out.append(line)
path.write_text("\n".join(out) + "\n")
PY
}

install_system_mode() {
  if [[ "${EUID}" -ne 0 ]] && ! has_sudo; then
    die "system mode needs root or sudo. Use --mode user for non-root installation."
  fi
  command -v systemctl >/dev/null 2>&1 || die "system mode needs systemd/systemctl. Use --mode user on this host."
  [[ -d /run/systemd/system ]] || die "system mode needs a running systemd host. Use --mode user on this host."

  install_args=(--enable --no-doctor)
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    install_args+=(--start)
  else
    install_args+=(--no-start)
  fi

  VELOXHASH_HTTP_HOST="${HTTP_HOST}" VELOXHASH_HTTP_PORT="${HTTP_PORT}" run_as_root "${SOURCE_DIR}/scripts/install-systemd-service.sh" "${install_args[@]}"

  write_system_env_value VELOXHASH_POOL_URL "${POOL_URL}"
  write_system_env_value VELOXHASH_POOL_PASSWORD "${POOL_PASSWORD}"
  write_system_env_value VELOXHASH_POOL_TLS "${POOL_TLS}"
  write_system_env_value VELOXHASH_COIN "${COIN}"
  write_system_env_value VELOXHASH_RIG_ID "${RIG_ID}"
  write_system_env_value VELOXHASH_POLICY_CPU_PERCENT "${CPU_PERCENT}"

  if [[ -n "${WALLET}" ]]; then
    write_system_env_value VELOXHASH_WALLET_ADDRESS "${WALLET}"
  fi

  if [[ "${POLICY_MODE}" == "off" ]]; then
    write_system_env_value VELOXHASH_POLICY_ENABLED 0
    if [[ -n "${WALLET}" ]]; then
      write_system_env_value VELOXHASH_MINING_ENABLED 1
    fi
    run_as_root systemctl disable --now veloxhash-policy.timer >/dev/null 2>&1 || true
    [[ "${START_SERVICE}" -eq 1 ]] && run_as_root systemctl restart veloxhash.service
  else
    write_system_env_value VELOXHASH_POLICY_ENABLED 1
    [[ "${START_SERVICE}" -eq 1 ]] && run_as_root systemctl enable --now veloxhash-policy.timer >/dev/null 2>&1
    [[ "${START_SERVICE}" -eq 1 ]] && run_as_root /usr/local/bin/veloxhash-policy run
  fi

  if [[ "${START_SERVICE}" -eq 1 ]]; then
    run_as_root env VELOXHASH_EXPECTED_HTTP_HOST="${HTTP_HOST}" VELOXHASH_EXPECTED_HTTP_PORT="${HTTP_PORT}" /usr/local/bin/veloxhash-validate
    run_as_root env VELOXHASH_DOCTOR_PORT="${HTTP_PORT}" /usr/local/bin/veloxhash-doctor
  fi

  cat <<EOF

VeloxHash system service installed.

Source/cache:
  ${SOURCE_DIR}

Dashboard:
  http://<server-ip>:${HTTP_PORT}/

Token:
  sudo veloxhash-mining token

Status:
  sudo veloxhash-status --short

Policy:
  ${POLICY_MODE}
EOF
}

write_user_config() {
  VELOXHASH_SELECTED_HTTP_HOST="${HTTP_HOST}" VELOXHASH_SELECTED_HTTP_PORT="${HTTP_PORT}" VELOXHASH_SELECTED_CPU_PERCENT="${CPU_PERCENT}" python3 - "${SOURCE_DIR}/config-mining.json" "${USER_CONFIG_FILE}" <<'PY'
from pathlib import Path
import json
import os
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
data = json.loads(src.read_text())
data["background"] = False
data["autosave"] = False
data["watch"] = False
data["log-file"] = str(dst.parent.parent / "logs" / "veloxhash.log")
http = data.setdefault("http", {})
http["enabled"] = True
http["host"] = os.environ["VELOXHASH_SELECTED_HTTP_HOST"]
http["port"] = int(os.environ["VELOXHASH_SELECTED_HTTP_PORT"])
http["access-token"] = None
http["restricted"] = True
cpu = data.setdefault("cpu", {})
cpu["enabled"] = True
cpu["yield"] = True
cpu["max-threads-hint"] = int(os.environ.get("VELOXHASH_SELECTED_CPU_PERCENT", "75"))
pools = data.setdefault("pools", [])
if not pools:
    pools.append({})
pool = pools[0]
pool["url"] = "${VELOXHASH_POOL_URL}"
pool["user"] = "${VELOXHASH_WALLET_ADDRESS}"
pool["pass"] = "${VELOXHASH_POOL_PASSWORD}"
pool["rig-id"] = "${VELOXHASH_RIG_ID}"
pool["coin"] = "${VELOXHASH_COIN}"
pool["tls"] = os.environ.get("VELOXHASH_POOL_TLS", "1").lower() in ("1", "true", "yes", "on")
pool["enabled"] = True
dst.write_text(json.dumps(data, indent=4) + "\n")
PY
}

write_user_runner() {
  cat > "${USER_RUNNER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${VELOXHASH_API_TOKEN:?VELOXHASH_API_TOKEN is required}"
: "${VELOXHASH_USER_PREFIX:?VELOXHASH_USER_PREFIX is required}"

CONFIG_FILE="${VELOXHASH_USER_PREFIX}/config/config.json"
LOG_FILE="${VELOXHASH_USER_PREFIX}/logs/veloxhash.log"
BINARY="${VELOXHASH_USER_PREFIX}/bin/veloxhash"

ARGS=(
  --config="${CONFIG_FILE}"
  --http-host="${VELOXHASH_HTTP_HOST:-0.0.0.0}"
  --http-port="${VELOXHASH_HTTP_PORT:-8089}"
  --http-access-token="${VELOXHASH_API_TOKEN}"
  --http-no-restricted
  --log-file="${LOG_FILE}"
  --no-huge-pages
  --randomx-wrmsr=-1
  --pause-on-active=900
)

truthy() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

is_wallet_configured() {
  local value="${1:-}"
  [[ -n "${value}" ]] || return 1
  [[ "${value}" != "YOUR_WALLET_ADDRESS" ]] || return 1
  [[ "${value}" != "\${VELOXHASH_WALLET_ADDRESS}" ]] || return 1
  [[ ! "${value}" =~ ^[[:space:]]+$ ]] || return 1
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

case "${VELOXHASH_MINING_ENABLED:-0}" in
  1|true|TRUE|yes|YES|on|ON)
    if is_wallet_configured "${VELOXHASH_WALLET_ADDRESS:-}"; then
      rig_id="${VELOXHASH_RIG_ID:-}"
      if [[ -z "${rig_id}" ]]; then
        rig_id="$(default_rig_id)"
      fi
      ARGS+=(
        --url="${VELOXHASH_POOL_URL:-auto.c3pool.org:33333}"
        --user="${VELOXHASH_WALLET_ADDRESS}"
        --pass="${VELOXHASH_POOL_PASSWORD:-x}"
        --rig-id="${rig_id}"
        --coin="${VELOXHASH_COIN:-monero}"
        --cpu-max-threads-hint="${VELOXHASH_POLICY_CPU_PERCENT:-75}"
        --donate-level=0
      )
      if truthy "${VELOXHASH_POOL_TLS:-1}"; then
        ARGS+=(--tls)
      fi
    else
      printf '%s\n' "VeloxHash wallet address is not configured; keeping CPU mining disabled." >&2
      ARGS+=(--no-cpu)
    fi
    ;;
  *)
    ARGS+=(--no-cpu)
    ;;
esac

exec "${BINARY}" "${ARGS[@]}"
EOF
  chmod 0755 "${USER_RUNNER}"
}

write_user_ctl() {
  cat > "${USER_CTL}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PREFIX}/config/veloxhash.env"
PID_FILE="${PREFIX}/state/veloxhash.pid"
SERVICE_NAME="veloxhash.service"

usage() {
  cat <<'HELP'
Usage: veloxhash-user <command>

Commands:
  start       Start user-mode VeloxHash
  stop        Stop user-mode VeloxHash
  restart     Restart user-mode VeloxHash
  status      Show service/process status
  token       Print dashboard/API token
  wallet      Show configured wallet status
  wallet set <address>
              Set public wallet address and restart
  pool        Show configured pool
  pool set <url> [password] [coin]
              Set pool URL, optional password, optional coin, and restart
  enable      Enable mining and restart
  disable     Disable mining and restart
HELP
}

set_env_value() {
  local key="$1"
  local value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
line = f"{key}={value}"
lines = path.read_text().splitlines() if path.exists() else []
out = []
updated = False
for item in lines:
    if item.startswith(f"{key}="):
        out.append(line)
        updated = True
    else:
        out.append(item)
if not updated:
    out.append(line)
path.write_text("\n".join(out) + "\n")
PY
}

get_env_value() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

has_user_systemd() {
  systemctl --user show-environment >/dev/null 2>&1
}

pid_alive() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

start_background() {
  if pid_alive; then
    echo "VeloxHash already running with PID $(cat "$PID_FILE")."
    return
  fi

  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  nohup "${PREFIX}/bin/veloxhash-run" >>"${PREFIX}/logs/veloxhash.out" 2>&1 &
  echo "$!" > "$PID_FILE"
  echo "VeloxHash started with PID $(cat "$PID_FILE")."
}

stop_background() {
  if ! pid_alive; then
    rm -f "$PID_FILE"
    echo "VeloxHash is not running."
    return
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  kill "$pid" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      rm -f "$PID_FILE"
      echo "VeloxHash stopped."
      return
    fi
    sleep 1
  done
  kill -9 "$pid" >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  echo "VeloxHash stopped."
}

start_service() {
  if has_user_systemd && [[ -f "${HOME}/.config/systemd/user/${SERVICE_NAME}" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE_NAME" >/dev/null 2>&1 || systemctl --user start "$SERVICE_NAME"
  else
    start_background
  fi
}

stop_service() {
  if has_user_systemd && systemctl --user list-unit-files "$SERVICE_NAME" >/dev/null 2>&1; then
    systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  stop_background
}

restart_service() {
  stop_service
  start_service
}

validate_public_wallet() {
  local wallet="$1"
  [[ -n "$wallet" ]] || { echo "Wallet address is empty." >&2; exit 1; }
  [[ ! "$wallet" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Refusing value that looks like a private key." >&2; exit 1; }
  [[ ! "$wallet" =~ [[:space:]] ]] || { echo "Wallet address must not contain whitespace." >&2; exit 1; }
}

validate_pool_url() {
  local url="$1"
  [[ -n "$url" ]] || { echo "Pool URL is empty." >&2; exit 1; }
  [[ ! "$url" =~ [[:space:]] ]] || { echo "Pool URL must not contain whitespace." >&2; exit 1; }
  [[ "$url" == *:* ]] || { echo "Pool URL should include host:port." >&2; exit 1; }
}

command="${1:-}"
sub="${2:-}"

case "$command" in
  start) start_service ;;
  stop) stop_service ;;
  restart) restart_service ;;
  status)
    if has_user_systemd && systemctl --user status "$SERVICE_NAME" --no-pager >/dev/null 2>&1; then
      systemctl --user status "$SERVICE_NAME" --no-pager
    elif pid_alive; then
      echo "VeloxHash running with PID $(cat "$PID_FILE")."
    else
      echo "VeloxHash is not running."
    fi
    ;;
  token)
    get_env_value VELOXHASH_API_TOKEN
    ;;
  wallet)
    case "$sub" in
      set)
        wallet="${3:-}"
        validate_public_wallet "$wallet"
        set_env_value VELOXHASH_WALLET_ADDRESS "$wallet"
        restart_service
        echo "VeloxHash public wallet address configured."
        ;;
      "")
        wallet="$(get_env_value VELOXHASH_WALLET_ADDRESS)"
        if [[ -n "$wallet" ]]; then
          echo "wallet: configured"
          echo "$wallet"
        else
          echo "wallet: not configured"
        fi
        ;;
      *) usage; exit 2 ;;
    esac
    ;;
  pool)
    case "$sub" in
      set)
        pool_url="${3:-}"
        pool_password="${4:-x}"
        coin="${5:-monero}"
        validate_pool_url "$pool_url"
        [[ ! "$pool_password" =~ [[:space:]] ]] || { echo "Pool password must not contain whitespace." >&2; exit 1; }
        [[ ! "$coin" =~ [[:space:]] ]] || { echo "Coin must not contain whitespace." >&2; exit 1; }
        set_env_value VELOXHASH_POOL_URL "$pool_url"
        set_env_value VELOXHASH_POOL_PASSWORD "$pool_password"
        set_env_value VELOXHASH_COIN "$coin"
        restart_service
        echo "VeloxHash pool configured."
        echo "pool: $pool_url"
        ;;
      "")
        echo "pool: $(get_env_value VELOXHASH_POOL_URL)"
        echo "password: $(get_env_value VELOXHASH_POOL_PASSWORD)"
        echo "coin: $(get_env_value VELOXHASH_COIN)"
        ;;
      *) usage; exit 2 ;;
    esac
    ;;
  enable)
    set_env_value VELOXHASH_MINING_ENABLED 1
    restart_service
    echo "VeloxHash mining enabled."
    ;;
  disable)
    set_env_value VELOXHASH_MINING_ENABLED 0
    restart_service
    echo "VeloxHash mining disabled. Dashboard/API remain online."
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 2
    ;;
esac
EOF
  chmod 0755 "${USER_CTL}"
}

install_user_mode() {
  local boot_start_state="not configured"

  install -d -m 0700 "${USER_PREFIX}" "${USER_CONFIG_DIR}" "${USER_STATE_DIR}" "${USER_LOG_DIR}"
  install -d -m 0755 "${USER_PREFIX}/bin"
  install -m 0755 "${SOURCE_DIR}/build-veloxhash/veloxhash" "${USER_BIN}"
  write_user_config
  write_user_runner
  write_user_ctl

  if [[ ! -f "${USER_ENV_FILE}" ]]; then
    {
      printf 'VELOXHASH_USER_PREFIX=%s\n' "${USER_PREFIX}"
      printf 'VELOXHASH_API_TOKEN=%s\n' "$(random_token)"
      printf 'VELOXHASH_HTTP_HOST=%s\n' "${HTTP_HOST}"
      printf 'VELOXHASH_HTTP_PORT=%s\n' "${HTTP_PORT}"
      printf 'VELOXHASH_WALLET_ADDRESS=%s\n' "${WALLET}"
      printf 'VELOXHASH_POOL_URL=%s\n' "${POOL_URL}"
      printf 'VELOXHASH_POOL_PASSWORD=%s\n' "${POOL_PASSWORD}"
      printf 'VELOXHASH_POOL_TLS=%s\n' "${POOL_TLS}"
      printf 'VELOXHASH_COIN=%s\n' "${COIN}"
      printf 'VELOXHASH_RIG_ID=%s\n' "${RIG_ID}"
      if [[ -n "${WALLET}" ]]; then
        printf 'VELOXHASH_MINING_ENABLED=1\n'
      else
        printf 'VELOXHASH_MINING_ENABLED=0\n'
      fi
      if [[ "${POLICY_MODE}" == "off" ]]; then
        printf 'VELOXHASH_POLICY_ENABLED=0\n'
      else
        printf 'VELOXHASH_POLICY_ENABLED=1\n'
      fi
      printf 'VELOXHASH_POLICY_CPU_PERCENT=%s\n' "${CPU_PERCENT}"
    } > "${USER_ENV_FILE}"
    chmod 0600 "${USER_ENV_FILE}"
  else
    write_env_value "${USER_ENV_FILE}" VELOXHASH_USER_PREFIX "${USER_PREFIX}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_HTTP_HOST "${HTTP_HOST}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_HTTP_PORT "${HTTP_PORT}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_POOL_URL "${POOL_URL}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_POOL_PASSWORD "${POOL_PASSWORD}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_POOL_TLS "${POOL_TLS}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_COIN "${COIN}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_RIG_ID "${RIG_ID}"
    write_env_value "${USER_ENV_FILE}" VELOXHASH_POLICY_CPU_PERCENT "${CPU_PERCENT}"
    if [[ "${POLICY_MODE}" == "off" ]]; then
      write_env_value "${USER_ENV_FILE}" VELOXHASH_POLICY_ENABLED 0
    else
      write_env_value "${USER_ENV_FILE}" VELOXHASH_POLICY_ENABLED 1
    fi
    [[ -n "$(sed -n 's/^VELOXHASH_API_TOKEN=//p' "${USER_ENV_FILE}" | tail -n 1)" ]] || write_env_value "${USER_ENV_FILE}" VELOXHASH_API_TOKEN "$(random_token)"
    if [[ -n "${WALLET}" ]]; then
      write_env_value "${USER_ENV_FILE}" VELOXHASH_WALLET_ADDRESS "${WALLET}"
      write_env_value "${USER_ENV_FILE}" VELOXHASH_MINING_ENABLED 1
    fi
  fi

  if [[ "${START_SERVICE}" -eq 0 ]]; then
    user_service_state="not started"
  elif systemctl --user show-environment >/dev/null 2>&1; then
    mkdir -p "${USER_SERVICE_DIR}"
    cat > "${USER_SERVICE_FILE}" <<EOF
[Unit]
Description=VeloxHash user service
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
EnvironmentFile=${USER_ENV_FILE}
WorkingDirectory=${USER_STATE_DIR}
ExecStart=${USER_RUNNER}
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now veloxhash.service >/dev/null 2>&1 || systemctl --user start veloxhash.service
    user_service_state="systemd user service"
    if [[ "${ENABLE_BOOT}" -eq 1 ]]; then
      if enable_user_linger_if_possible "$(id -un)"; then
        boot_start_state="enabled with loginctl linger"
      else
        boot_start_state="needs administrator: loginctl enable-linger $(id -un)"
      fi
    else
      boot_start_state="disabled by --no-enable-boot"
    fi
  else
    "${USER_CTL}" start
    user_service_state="background process"
    boot_start_state="not available without user systemd"
  fi

  user_api_token="$(sed -n 's/^VELOXHASH_API_TOKEN=//p' "${USER_ENV_FILE}" | tail -n 1)"
  if [[ -z "${user_api_token}" ]]; then
    user_api_token="<read with: ${USER_CTL} token>"
  fi

  cat <<EOF

VeloxHash user-mode installation complete.

Mode:
  ${user_service_state}

Source/cache:
  ${SOURCE_DIR}

Runtime:
  ${USER_PREFIX}

Dashboard:
  http://<server-ip>:${HTTP_PORT}/

Token:
  ${user_api_token}

Token command:
  ${USER_CTL} token

Status:
  ${USER_CTL} status

Boot startup:
  ${boot_start_state}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --wallet)
      [[ $# -ge 2 ]] || die "--wallet requires a value"
      WALLET="$2"
      shift
      ;;
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      MODE="$2"
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
      USER_PREFIX="${CACHE_ROOT}/runtime"
      USER_BIN="${USER_PREFIX}/bin/veloxhash"
      USER_CONFIG_DIR="${USER_PREFIX}/config"
      USER_STATE_DIR="${USER_PREFIX}/state"
      USER_LOG_DIR="${USER_PREFIX}/logs"
      USER_RUNNER="${USER_PREFIX}/bin/veloxhash-run"
      USER_CTL="${USER_PREFIX}/bin/veloxhash-user"
      USER_ENV_FILE="${USER_CONFIG_DIR}/veloxhash.env"
      USER_CONFIG_FILE="${USER_CONFIG_DIR}/config.json"
      shift
      ;;
    --http-host)
      [[ $# -ge 2 ]] || die "--http-host requires a value"
      HTTP_HOST="$2"
      shift
      ;;
    --http-port)
      [[ $# -ge 2 ]] || die "--http-port requires a value"
      HTTP_PORT="$2"
      shift
      ;;
    --http-port-max)
      [[ $# -ge 2 ]] || die "--http-port-max requires a value"
      HTTP_PORT_MAX="$2"
      shift
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
    --pool-tls)
      POOL_TLS=1
      ;;
    --no-pool-tls)
      POOL_TLS=0
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
    --cpu-percent)
      [[ $# -ge 2 ]] || die "--cpu-percent requires a value"
      CPU_PERCENT="$2"
      shift
      ;;
    --policy)
      [[ $# -ge 2 ]] || die "--policy requires a value"
      POLICY_MODE="$2"
      shift
      ;;
    --skip-apt)
      SKIP_APT=1
      ;;
    --skip-source-update)
      SKIP_SOURCE_UPDATE=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --no-start)
      START_SERVICE=0
      ;;
    --no-enable-boot)
      ENABLE_BOOT=0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "${WALLET}" || "${WALLET}" == "$1" ]] || die "wallet address was provided more than once"
      WALLET="$1"
      ;;
  esac
  shift
done

case "${MODE}" in
  auto|system|user) ;;
  *) die "--mode must be auto, system, or user" ;;
esac

validate_public_wallet "${WALLET}"
validate_pool_settings
detect_os
ARCH="$(detect_arch)"
detect_pkg_manager
install_deps_if_allowed
if [[ "${SKIP_SOURCE_UPDATE}" -eq 0 ]]; then
  update_source
fi
build_source

if [[ "${MODE}" == "auto" ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    MODE="system"
  else
    MODE="user"
  fi
fi

HTTP_PORT="$(select_http_port "${HTTP_PORT}" "${HTTP_PORT_MAX}")"

cat <<EOF
VeloxHash bootstrap summary:
  system: ${OS_NAME}
  architecture: ${ARCH}
  package manager: ${PKG_MANAGER}
  mode: ${MODE}
  cache: ${CACHE_ROOT}
  source: ${SOURCE_DIR}
  http: ${HTTP_HOST}:${HTTP_PORT}
  pool: ${POOL_URL}
  pool tls: ${POOL_TLS}
  coin: ${COIN}
  rig-id: ${RIG_ID:-auto}
  cpu-percent: ${CPU_PERCENT}
  policy: ${POLICY_MODE}
  start now: ${START_SERVICE}
EOF

case "${MODE}" in
  system) install_system_mode ;;
  user) install_user_mode ;;
esac
