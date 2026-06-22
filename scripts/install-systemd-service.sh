#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${ROOT_DIR}/build-veloxhash/veloxhash"
CONFIG_SOURCE="${ROOT_DIR}/config-mining.json"
SERVICE_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash.service"
POLICY_SERVICE_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-policy.service"
POLICY_TIMER_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-policy.timer"
CLUSTER_PRIMARY_SERVICE_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-cluster-primary.service"
CLUSTER_HEARTBEAT_SERVICE_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.service"
CLUSTER_HEARTBEAT_TIMER_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-cluster-heartbeat.timer"
RUNNER_SOURCE="${ROOT_DIR}/deploy/systemd/veloxhash-run"
LOGROTATE_SOURCE="${ROOT_DIR}/deploy/logrotate/veloxhash"
MINING_CTL_SOURCE="${ROOT_DIR}/scripts/veloxhash-mining"
POLICY_SOURCE="${ROOT_DIR}/scripts/veloxhash-policy"
CLUSTER_SOURCE="${ROOT_DIR}/scripts/veloxhash-cluster"
DOCTOR_SOURCE="${ROOT_DIR}/scripts/veloxhash-doctor"
STATUS_SOURCE="${ROOT_DIR}/scripts/veloxhash-status"
VALIDATE_SOURCE="${ROOT_DIR}/scripts/veloxhash-validate"
BACKUP_SOURCE="${ROOT_DIR}/scripts/veloxhash-backup"
RESTORE_SOURCE="${ROOT_DIR}/scripts/veloxhash-restore"
UNINSTALL_SOURCE="${ROOT_DIR}/scripts/uninstall-systemd-service.sh"
UPGRADE_SOURCE="${ROOT_DIR}/scripts/veloxhash-upgrade"

ENABLE_SERVICE=1
START_SERVICE=1
RUN_DOCTOR=1
HTTP_HOST="${VELOXHASH_HTTP_HOST:-0.0.0.0}"
HTTP_PORT="${VELOXHASH_HTTP_PORT:-8089}"
HTTP_PORT_MAX="${VELOXHASH_HTTP_PORT_MAX:-8189}"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install-systemd-service.sh [options]

Installs the current VeloxHash build as a stable systemd service.

Default behavior:
  - enable veloxhash.service at boot
  - start or restart veloxhash.service now
  - enable and start veloxhash-policy.timer
  - run validation and doctor checks

Options:
  --enable      Enable veloxhash.service at boot (default)
  --start       Start or restart veloxhash.service after installation (default)
  --doctor      Run veloxhash-doctor after installation (default)
  --no-enable   Install files without enabling boot startup
  --no-start    Install files without starting/restarting services
  --no-doctor   Skip validation and doctor checks
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable)
      ENABLE_SERVICE=1
      ;;
    --start)
      START_SERVICE=1
      ;;
    --doctor)
      RUN_DOCTOR=1
      ;;
    --no-enable)
      ENABLE_SERVICE=0
      ;;
    --no-start)
      START_SERVICE=0
      ;;
    --no-doctor)
      RUN_DOCTOR=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run with sudo." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
  echo "systemd/systemctl is required for system service installation." >&2
  echo "Use scripts/bootstrap-cache-install.sh --mode user on non-systemd hosts." >&2
  exit 1
fi

set_env_value_file() {
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

  echo "No free HTTP port found in ${start}-${max}." >&2
  exit 1
}

HTTP_PORT="$(select_http_port "${HTTP_PORT}" "${HTTP_PORT_MAX}")"

if [[ ! -x "${BINARY}" ]]; then
  echo "Missing binary: ${BINARY}" >&2
  echo "Build it first: cmake --build build-veloxhash -j\$(nproc)" >&2
  exit 1
fi

if [[ ! -f "${SERVICE_SOURCE}" ]]; then
  echo "Missing service template: ${SERVICE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${POLICY_SERVICE_SOURCE}" ]]; then
  echo "Missing policy service template: ${POLICY_SERVICE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${POLICY_TIMER_SOURCE}" ]]; then
  echo "Missing policy timer template: ${POLICY_TIMER_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${CLUSTER_PRIMARY_SERVICE_SOURCE}" ]]; then
  echo "Missing cluster primary service template: ${CLUSTER_PRIMARY_SERVICE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${CLUSTER_HEARTBEAT_SERVICE_SOURCE}" ]]; then
  echo "Missing cluster heartbeat service template: ${CLUSTER_HEARTBEAT_SERVICE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${CLUSTER_HEARTBEAT_TIMER_SOURCE}" ]]; then
  echo "Missing cluster heartbeat timer template: ${CLUSTER_HEARTBEAT_TIMER_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${RUNNER_SOURCE}" ]]; then
  echo "Missing service runner: ${RUNNER_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${LOGROTATE_SOURCE}" ]]; then
  echo "Missing logrotate config: ${LOGROTATE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${MINING_CTL_SOURCE}" ]]; then
  echo "Missing mining control script: ${MINING_CTL_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${POLICY_SOURCE}" ]]; then
  echo "Missing policy script: ${POLICY_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${CLUSTER_SOURCE}" ]]; then
  echo "Missing cluster script: ${CLUSTER_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${DOCTOR_SOURCE}" ]]; then
  echo "Missing doctor script: ${DOCTOR_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${STATUS_SOURCE}" ]]; then
  echo "Missing status script: ${STATUS_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${VALIDATE_SOURCE}" ]]; then
  echo "Missing validate script: ${VALIDATE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${BACKUP_SOURCE}" ]]; then
  echo "Missing backup script: ${BACKUP_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${RESTORE_SOURCE}" ]]; then
  echo "Missing restore script: ${RESTORE_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${UNINSTALL_SOURCE}" ]]; then
  echo "Missing uninstall script: ${UNINSTALL_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${UPGRADE_SOURCE}" ]]; then
  echo "Missing upgrade script: ${UPGRADE_SOURCE}" >&2
  exit 1
fi

detect_and_cleanup_legacy() {
  local legacy_found=0

  if [[ -f /usr/local/lib/veloxhash/veloxhash-run ]] && ! grep -q -- '--url=' /usr/local/lib/veloxhash/veloxhash-run; then
    legacy_found=1
    install -d -m 0750 /var/backups/veloxhash
    cp -a /usr/local/lib/veloxhash/veloxhash-run "/var/backups/veloxhash/veloxhash-run.legacy.$(date +%Y%m%d%H%M%S)"
    echo "Legacy VeloxHash runner detected; backed it up and replacing it."
  fi

  for path in \
    /usr/local/bin/xmrig \
    /usr/local/bin/myxmrig \
    /usr/local/bin/veloxhash-run \
    /etc/systemd/system/xmrig.service \
    /etc/systemd/system/myxmrig.service
  do
    if [[ -e "${path}" ]]; then
      legacy_found=1
      install -d -m 0750 /var/backups/veloxhash
      mv "${path}" "/var/backups/veloxhash/$(basename "${path}").legacy.$(date +%Y%m%d%H%M%S)"
      echo "Moved legacy path to /var/backups/veloxhash: ${path}"
    fi
  done

  if systemctl list-unit-files xmrig.service myxmrig.service >/dev/null 2>&1; then
    systemctl disable --now xmrig.service myxmrig.service >/dev/null 2>&1 || true
  fi

  if [[ "${legacy_found}" -eq 1 ]]; then
    systemctl daemon-reload
  fi
}

detect_and_cleanup_legacy

install -D -m 0755 "${BINARY}" /usr/local/bin/veloxhash
install -D -m 0755 "${RUNNER_SOURCE}" /usr/local/lib/veloxhash/veloxhash-run
install -D -m 0755 "${MINING_CTL_SOURCE}" /usr/local/bin/veloxhash-mining
install -D -m 0755 "${POLICY_SOURCE}" /usr/local/bin/veloxhash-policy
install -D -m 0755 "${CLUSTER_SOURCE}" /usr/local/bin/veloxhash-cluster
install -D -m 0755 "${DOCTOR_SOURCE}" /usr/local/bin/veloxhash-doctor
install -D -m 0755 "${STATUS_SOURCE}" /usr/local/bin/veloxhash-status
install -D -m 0755 "${VALIDATE_SOURCE}" /usr/local/bin/veloxhash-validate
install -D -m 0755 "${BACKUP_SOURCE}" /usr/local/bin/veloxhash-backup
install -D -m 0755 "${RESTORE_SOURCE}" /usr/local/bin/veloxhash-restore
install -D -m 0755 "${UNINSTALL_SOURCE}" /usr/local/bin/veloxhash-uninstall
install -D -m 0755 "${UPGRADE_SOURCE}" /usr/local/bin/veloxhash-upgrade
install -D -m 0644 "${LOGROTATE_SOURCE}" /etc/logrotate.d/veloxhash

if ! id -u veloxhash >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/veloxhash --create-home --shell /usr/sbin/nologin veloxhash
fi

install -d -m 0750 -o veloxhash -g veloxhash /etc/veloxhash /var/lib/veloxhash /var/log/veloxhash

if [[ ! -f /etc/veloxhash/config.json ]]; then
  if [[ -f "${CONFIG_SOURCE}" ]]; then
    install -m 0640 -o veloxhash -g veloxhash "${CONFIG_SOURCE}" /etc/veloxhash/config.json
  else
    install -m 0640 -o veloxhash -g veloxhash "${ROOT_DIR}/src/config.json" /etc/veloxhash/config.json
  fi
fi

VELOXHASH_SELECTED_HTTP_HOST="${HTTP_HOST}" VELOXHASH_SELECTED_HTTP_PORT="${HTTP_PORT}" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path("/etc/veloxhash/config.json")
data = json.loads(path.read_text())
data["background"] = False
data["autosave"] = False
data["watch"] = False
http = data.setdefault("http", {})
http["enabled"] = True
http["host"] = os.environ["VELOXHASH_SELECTED_HTTP_HOST"]
http["port"] = int(os.environ["VELOXHASH_SELECTED_HTTP_PORT"])
http["access-token"] = None
http["restricted"] = True
cpu = data.setdefault("cpu", {})
cpu["enabled"] = True
cpu["yield"] = True
cpu["max-threads-hint"] = 75
pools = data.setdefault("pools", [])
if pools:
    pool = pools[0]
else:
    pool = {}
    pools.append(pool)
pool["url"] = "127.0.0.1:1"
pool["user"] = "disabled"
pool["pass"] = "x"
pool["rig-id"] = None
pool["coin"] = None
pool["tls"] = False
pool["enabled"] = False
path.write_text(json.dumps(data, indent=4) + "\n")
PY
chown veloxhash:veloxhash /etc/veloxhash/config.json
chmod 0640 /etc/veloxhash/config.json

if [[ ! -f /etc/veloxhash/veloxhash.env ]]; then
  if command -v openssl >/dev/null 2>&1; then
    TOKEN="$(openssl rand -hex 24)"
  else
    TOKEN="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)"
  fi
  umask 0077
  {
    printf 'VELOXHASH_API_TOKEN=%s\n' "${TOKEN}"
    printf 'VELOXHASH_HTTP_HOST=%s\n' "${HTTP_HOST}"
    printf 'VELOXHASH_HTTP_PORT=%s\n' "${HTTP_PORT}"
    printf 'VELOXHASH_WALLET_ADDRESS=\n'
    printf 'VELOXHASH_POOL_URL=auto.c3pool.org:33333\n'
    printf 'VELOXHASH_POOL_PASSWORD=x\n'
    printf 'VELOXHASH_POOL_TLS=1\n'
    printf 'VELOXHASH_COIN=monero\n'
    printf 'VELOXHASH_RIG_ID=\n'
    printf 'VELOXHASH_MINING_ENABLED=0\n'
    printf 'VELOXHASH_POLICY_ENABLED=1\n'
    printf 'VELOXHASH_POLICY_CPU_PERCENT=75\n'
    printf 'VELOXHASH_POLICY_WORK_START=08\n'
    printf 'VELOXHASH_POLICY_WORK_END=22\n'
    printf 'VELOXHASH_POLICY_LOAD_THRESHOLD=0.60\n'
    printf 'VELOXHASH_POLICY_ACTIVE_MINUTES=15\n'
    printf 'VELOXHASH_CLUSTER_ENABLED=0\n'
    printf 'VELOXHASH_CLUSTER_ROLE=standalone\n'
    printf 'VELOXHASH_CLUSTER_HOST=0.0.0.0\n'
    printf 'VELOXHASH_CLUSTER_PORT=8090\n'
    printf 'VELOXHASH_CLUSTER_NODE_ID=\n'
    printf 'VELOXHASH_CLUSTER_NODE_NAME=\n'
    printf 'VELOXHASH_CLUSTER_STALE_SECONDS=180\n'
  } > /etc/veloxhash/veloxhash.env
  chown root:veloxhash /etc/veloxhash/veloxhash.env
  chmod 0640 /etc/veloxhash/veloxhash.env
else
  set_env_value_file /etc/veloxhash/veloxhash.env VELOXHASH_HTTP_HOST "${HTTP_HOST}"
  set_env_value_file /etc/veloxhash/veloxhash.env VELOXHASH_HTTP_PORT "${HTTP_PORT}"
  if ! grep -q '^VELOXHASH_WALLET_ADDRESS=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_WALLET_ADDRESS=\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POOL_URL=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POOL_URL=auto.c3pool.org:33333\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POOL_PASSWORD=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POOL_PASSWORD=x\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POOL_TLS=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POOL_TLS=1\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_COIN=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_COIN=monero\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_RIG_ID=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_RIG_ID=\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_MINING_ENABLED=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_MINING_ENABLED=0\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POLICY_ENABLED=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_ENABLED=1\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POLICY_CPU_PERCENT=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_CPU_PERCENT=75\n' >> /etc/veloxhash/veloxhash.env
  elif grep -q '^VELOXHASH_POLICY_CPU_PERCENT=50$' /etc/veloxhash/veloxhash.env; then
    set_env_value_file /etc/veloxhash/veloxhash.env VELOXHASH_POLICY_CPU_PERCENT 75
  fi
  if ! grep -q '^VELOXHASH_POLICY_WORK_START=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_WORK_START=08\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POLICY_WORK_END=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_WORK_END=22\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POLICY_LOAD_THRESHOLD=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_LOAD_THRESHOLD=0.60\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_POLICY_ACTIVE_MINUTES=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_POLICY_ACTIVE_MINUTES=15\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_ENABLED=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_ENABLED=0\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_ROLE=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_ROLE=standalone\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_HOST=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_HOST=0.0.0.0\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_PORT=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_PORT=8090\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_NODE_ID=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_NODE_ID=\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_NODE_NAME=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_NODE_NAME=\n' >> /etc/veloxhash/veloxhash.env
  fi
  if ! grep -q '^VELOXHASH_CLUSTER_STALE_SECONDS=' /etc/veloxhash/veloxhash.env; then
    printf 'VELOXHASH_CLUSTER_STALE_SECONDS=180\n' >> /etc/veloxhash/veloxhash.env
  fi
  chown root:veloxhash /etc/veloxhash/veloxhash.env
  chmod 0640 /etc/veloxhash/veloxhash.env
fi

write_install_info() {
  local service_enabled active_state sub_state main_pid restarts binary_version git_commit git_branch git_dirty

  service_enabled="$(systemctl is-enabled veloxhash.service 2>/dev/null || true)"
  active_state="$(systemctl show veloxhash.service -p ActiveState --value 2>/dev/null || true)"
  sub_state="$(systemctl show veloxhash.service -p SubState --value 2>/dev/null || true)"
  main_pid="$(systemctl show veloxhash.service -p MainPID --value 2>/dev/null || true)"
  restarts="$(systemctl show veloxhash.service -p NRestarts --value 2>/dev/null || true)"
  binary_version="$(/usr/local/bin/veloxhash --version 2>/dev/null | sed -n '1,3p' || true)"

  git_commit=""
  git_branch=""
  git_dirty=""
  if command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_commit="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || true)"
    git_branch="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ -n "$(git -C "${ROOT_DIR}" status --short 2>/dev/null)" ]]; then
      git_dirty="true"
    else
      git_dirty="false"
    fi
  fi

  INSTALL_ROOT_DIR="${ROOT_DIR}" \
  INSTALL_BINARY_SOURCE="${BINARY}" \
  INSTALL_CONFIG_SOURCE="${CONFIG_SOURCE}" \
  INSTALL_SERVICE_SOURCE="${SERVICE_SOURCE}" \
  INSTALL_HTTP_HOST="${HTTP_HOST}" \
  INSTALL_HTTP_PORT="${HTTP_PORT}" \
  INSTALL_SERVICE_ENABLED="${service_enabled}" \
  INSTALL_ACTIVE_STATE="${active_state}" \
  INSTALL_SUB_STATE="${sub_state}" \
  INSTALL_MAIN_PID="${main_pid}" \
  INSTALL_RESTARTS="${restarts}" \
  INSTALL_BINARY_VERSION="${binary_version}" \
  INSTALL_GIT_COMMIT="${git_commit}" \
  INSTALL_GIT_BRANCH="${git_branch}" \
  INSTALL_GIT_DIRTY="${git_dirty}" \
  python3 - <<'PY'
import json
import os
import socket
from pathlib import Path
from datetime import datetime, timezone

info = {
    "installed_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": socket.gethostname(),
    "source_root": os.environ.get("INSTALL_ROOT_DIR", ""),
    "source_binary": os.environ.get("INSTALL_BINARY_SOURCE", ""),
    "source_config": os.environ.get("INSTALL_CONFIG_SOURCE", ""),
    "source_service": os.environ.get("INSTALL_SERVICE_SOURCE", ""),
    "binary": "/usr/local/bin/veloxhash",
    "config": "/etc/veloxhash/config.json",
    "env": "/etc/veloxhash/veloxhash.env",
    "service": "/etc/systemd/system/veloxhash.service",
    "runner": "/usr/local/lib/veloxhash/veloxhash-run",
    "dashboard_url": f"http://<server-ip>:{os.environ.get('INSTALL_HTTP_PORT', '8089')}/",
    "http_host": os.environ.get("INSTALL_HTTP_HOST", "0.0.0.0"),
    "http_port": int(os.environ.get("INSTALL_HTTP_PORT", "8089")),
    "mining_default": "disabled",
    "policy": {
        "enabled": True,
        "cpu_percent": 75,
        "work_start": "08",
        "work_end": "22",
        "load_threshold": 0.60,
        "active_minutes": 15,
        "check_interval": "1 minute",
        "timer": "veloxhash-policy.timer"
    },
    "cluster": {
        "enabled_default": False,
        "primary_service": "veloxhash-cluster-primary.service",
        "heartbeat_timer": "veloxhash-cluster-heartbeat.timer",
        "default_port": 8090,
        "stale_seconds": 180
    },
    "service_enabled": os.environ.get("INSTALL_SERVICE_ENABLED", ""),
    "active_state": os.environ.get("INSTALL_ACTIVE_STATE", ""),
    "sub_state": os.environ.get("INSTALL_SUB_STATE", ""),
    "main_pid": os.environ.get("INSTALL_MAIN_PID", ""),
    "restart_count": os.environ.get("INSTALL_RESTARTS", ""),
    "binary_version": os.environ.get("INSTALL_BINARY_VERSION", "").splitlines(),
    "git": {
        "branch": os.environ.get("INSTALL_GIT_BRANCH", ""),
        "commit": os.environ.get("INSTALL_GIT_COMMIT", ""),
        "dirty": os.environ.get("INSTALL_GIT_DIRTY", ""),
    },
}

path = Path("/etc/veloxhash/install-info.json")
path.write_text(json.dumps(info, indent=2) + "\n")
PY
  chown root:veloxhash /etc/veloxhash/install-info.json
  chmod 0640 /etc/veloxhash/install-info.json
}

cat > /etc/veloxhash/README.systemd <<EOF
VeloxHash systemd paths:

- binary: /usr/local/bin/veloxhash
- config: /etc/veloxhash/config.json
- environment token: /etc/veloxhash/veloxhash.env
- install record: /etc/veloxhash/install-info.json
- runner: /usr/local/lib/veloxhash/veloxhash-run
- mining control: /usr/local/bin/veloxhash-mining
- automatic policy: /usr/local/bin/veloxhash-policy
- cluster monitor: /usr/local/bin/veloxhash-cluster
- health check: /usr/local/bin/veloxhash-doctor
- status snapshot: /usr/local/bin/veloxhash-status
- validation: /usr/local/bin/veloxhash-validate
- backup: /usr/local/bin/veloxhash-backup
- restore: /usr/local/bin/veloxhash-restore
- uninstall: /usr/local/bin/veloxhash-uninstall
- upgrade: /usr/local/bin/veloxhash-upgrade
- backup directory: /var/backups/veloxhash
- log file: /var/log/veloxhash/veloxhash.log
- log rotation: /etc/logrotate.d/veloxhash
- dashboard: http://<server-ip>:${HTTP_PORT}/

CPU mining is controlled by the automatic policy. The dashboard/API remains online.
Mining requires a public wallet address. Never store a private key or seed phrase here.
Set the public payout address with:

  sudo veloxhash-mining wallet set <public-wallet-address>

Default policy: max 75% CPU, no mining when a non-service user was active in the last 15 minutes, no mining during 08:00-22:00, stop when load1 is above CPU cores * 0.60. The policy checks every minute.

Cluster monitoring is installed but disabled by default. It does not control mining. It only records node health heartbeats when explicitly enabled.

Control mining:

  sudo veloxhash-mining status
  sudo veloxhash-mining wallet
  sudo veloxhash-mining wallet set <public-wallet-address>
  sudo veloxhash-mining enable
  sudo veloxhash-mining disable
  sudo veloxhash-policy status
  sudo veloxhash-policy enable
  sudo veloxhash-policy disable
  sudo veloxhash-status
  sudo veloxhash-cluster status
  sudo veloxhash-validate
  sudo veloxhash-doctor

Backup and restore:

  sudo veloxhash-backup
  sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
  sudo veloxhash-upgrade
  sudo veloxhash-uninstall

Read the token:

  sudo sed -n 's/^VELOXHASH_API_TOKEN=//p' /etc/veloxhash/veloxhash.env
EOF
chmod 0644 /etc/veloxhash/README.systemd

install -m 0644 "${SERVICE_SOURCE}" /etc/systemd/system/veloxhash.service
install -m 0644 "${POLICY_SERVICE_SOURCE}" /etc/systemd/system/veloxhash-policy.service
install -m 0644 "${POLICY_TIMER_SOURCE}" /etc/systemd/system/veloxhash-policy.timer
install -m 0644 "${CLUSTER_PRIMARY_SERVICE_SOURCE}" /etc/systemd/system/veloxhash-cluster-primary.service
install -m 0644 "${CLUSTER_HEARTBEAT_SERVICE_SOURCE}" /etc/systemd/system/veloxhash-cluster-heartbeat.service
install -m 0644 "${CLUSTER_HEARTBEAT_TIMER_SOURCE}" /etc/systemd/system/veloxhash-cluster-heartbeat.timer
systemctl daemon-reload

if [[ "${ENABLE_SERVICE}" -eq 1 ]]; then
  systemctl enable veloxhash.service
  systemctl enable veloxhash-policy.timer
fi

if [[ "${START_SERVICE}" -eq 1 ]]; then
  if systemctl is-active --quiet veloxhash.service; then
    systemctl restart veloxhash.service
  else
    systemctl start veloxhash.service
  fi
  systemctl start veloxhash-policy.timer
  /usr/local/bin/veloxhash-policy run
fi

write_install_info

cat <<EOF
VeloxHash systemd installation complete.

Dashboard: http://<server-ip>:${HTTP_PORT}/
Token file: /etc/veloxhash/veloxhash.env
Install info: /etc/veloxhash/install-info.json
Mining default: disabled
Wallet default: not configured; mining will not start until a public wallet address is set
Policy default: enabled, 75% CPU, stop on recent user activity, off during 08:00-22:00, checks every minute

Commands:
  sudo systemctl status veloxhash
  sudo journalctl -u veloxhash -n 100 --no-pager
  sudo logrotate -d /etc/logrotate.d/veloxhash
  sudo veloxhash-mining status
  sudo veloxhash-mining wallet
  sudo veloxhash-mining wallet set <public-wallet-address>
  sudo veloxhash-mining enable
  sudo veloxhash-mining disable
  sudo veloxhash-policy status
  sudo veloxhash-policy enable
  sudo veloxhash-policy disable
  sudo veloxhash-status
  sudo veloxhash-cluster status
  sudo veloxhash-validate
  sudo veloxhash-backup
  sudo veloxhash-upgrade
  sudo veloxhash-uninstall
  sudo veloxhash-doctor
EOF

if [[ "${RUN_DOCTOR}" -eq 1 ]]; then
  echo
  if ! VELOXHASH_EXPECTED_HTTP_HOST="${HTTP_HOST}" VELOXHASH_EXPECTED_HTTP_PORT="${HTTP_PORT}" /usr/local/bin/veloxhash-validate; then
    echo
    echo "VeloxHash validation reported failures. Check the output above." >&2
    exit 1
  fi
  echo
  if ! VELOXHASH_DOCTOR_PORT="${HTTP_PORT}" /usr/local/bin/veloxhash-doctor; then
    echo
    echo "VeloxHash doctor reported failures. Check the output above." >&2
    exit 1
  fi
fi
