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
MODE="${VELOXHASH_INSTALL_MODE:-auto}"
SKIP_APT=0
SKIP_BUILD=0
START_SERVICE=1

usage() {
  cat <<'EOF'
Usage: bash bootstrap-cache-install.sh [public-wallet-address] [options]

Downloads/updates VeloxHash under ~/.cache/veloxhash/source and builds it for
the current host architecture.

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
  --skip-apt         Do not install apt build dependencies
  --skip-build       Install existing build output from the cached source tree
  --no-start         Install files without starting VeloxHash
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
    run_as_root apt-get update
    run_as_root apt-get install -y build-essential ca-certificates cmake curl git libuv1-dev libssl-dev libhwloc-dev
    return
  fi

  for cmd in git cmake; do
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

  install_args=(--enable)
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    install_args+=(--start)
  else
    install_args+=(--no-start)
  fi

  run_as_root "${SOURCE_DIR}/scripts/install-systemd-service.sh" "${install_args[@]}"

  if [[ -n "${WALLET}" ]]; then
    if [[ "${START_SERVICE}" -eq 1 ]]; then
      run_as_root /usr/local/bin/veloxhash-mining wallet set "${WALLET}"
    else
      write_system_env_value VELOXHASH_WALLET_ADDRESS "${WALLET}"
      write_system_env_value VELOXHASH_MINING_ENABLED 1
    fi
  fi

  cat <<EOF

VeloxHash system service installed.

Source/cache:
  ${SOURCE_DIR}

Dashboard:
  http://<server-ip>:8089/

Token:
  sudo veloxhash-mining token

Status:
  sudo veloxhash-status --short
EOF
}

write_user_config() {
  python3 - "${SOURCE_DIR}/config-mining.json" "${USER_CONFIG_FILE}" <<'PY'
from pathlib import Path
import json
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
http["host"] = "0.0.0.0"
http["port"] = 8089
http["access-token"] = None
http["restricted"] = True
cpu = data.setdefault("cpu", {})
cpu["enabled"] = True
cpu["yield"] = True
cpu["max-threads-hint"] = 50
pools = data.setdefault("pools", [])
if not pools:
    pools.append({})
pool = pools[0]
pool["url"] = "${VELOXHASH_POOL_URL}"
pool["user"] = "${VELOXHASH_WALLET_ADDRESS}"
pool["pass"] = "${VELOXHASH_POOL_PASSWORD}"
pool["rig-id"] = "${VELOXHASH_RIG_ID}"
pool["coin"] = "${VELOXHASH_COIN}"
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
  --http-host=0.0.0.0
  --http-port=8089
  --http-access-token="${VELOXHASH_API_TOKEN}"
  --http-no-restricted
  --log-file="${LOG_FILE}"
  --no-huge-pages
  --randomx-wrmsr=-1
  --pause-on-active=900
)

is_wallet_configured() {
  local value="${1:-}"
  [[ -n "${value}" ]] || return 1
  [[ "${value}" != "YOUR_WALLET_ADDRESS" ]] || return 1
  [[ "${value}" != "\${VELOXHASH_WALLET_ADDRESS}" ]] || return 1
  [[ ! "${value}" =~ ^[[:space:]]+$ ]] || return 1
}

case "${VELOXHASH_MINING_ENABLED:-0}" in
  1|true|TRUE|yes|YES|on|ON)
    if is_wallet_configured "${VELOXHASH_WALLET_ADDRESS:-}"; then
      rig_id="${VELOXHASH_RIG_ID:-}"
      if [[ -z "${rig_id}" ]]; then
        rig_id="$(hostname -s 2>/dev/null || printf 'veloxhash')"
      fi
      ARGS+=(
        --url="${VELOXHASH_POOL_URL:-pool.supportxmr.com:3333}"
        --user="${VELOXHASH_WALLET_ADDRESS}"
        --pass="${VELOXHASH_POOL_PASSWORD:-x}"
        --rig-id="${rig_id}"
        --coin="${VELOXHASH_COIN:-monero}"
        --cpu-max-threads-hint="${VELOXHASH_POLICY_CPU_PERCENT:-50}"
        --donate-level=0
      )
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
      printf 'VELOXHASH_WALLET_ADDRESS=%s\n' "${WALLET}"
      printf 'VELOXHASH_POOL_URL=pool.supportxmr.com:3333\n'
      printf 'VELOXHASH_POOL_PASSWORD=x\n'
      printf 'VELOXHASH_COIN=monero\n'
      printf 'VELOXHASH_RIG_ID=\n'
      if [[ -n "${WALLET}" ]]; then
        printf 'VELOXHASH_MINING_ENABLED=1\n'
      else
        printf 'VELOXHASH_MINING_ENABLED=0\n'
      fi
      printf 'VELOXHASH_POLICY_CPU_PERCENT=50\n'
    } > "${USER_ENV_FILE}"
    chmod 0600 "${USER_ENV_FILE}"
  else
    write_env_value "${USER_ENV_FILE}" VELOXHASH_USER_PREFIX "${USER_PREFIX}"
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
  else
    "${USER_CTL}" start
    user_service_state="background process"
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
  http://<server-ip>:8089/

Token:
  ${USER_CTL} token

Status:
  ${USER_CTL} status

Note:
  User-mode startup after reboot requires the user session to start again, or an
  administrator to enable linger with: loginctl enable-linger $(id -un)
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
    --skip-apt)
      SKIP_APT=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --no-start)
      START_SERVICE=0
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
install_deps_if_allowed
update_source
build_source

if [[ "${MODE}" == "auto" ]]; then
  if [[ "${EUID}" -eq 0 ]]; then
    MODE="system"
  else
    MODE="user"
  fi
fi

case "${MODE}" in
  system) install_system_mode ;;
  user) install_user_mode ;;
esac
