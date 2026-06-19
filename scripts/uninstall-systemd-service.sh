#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="veloxhash.service"
KEEP_DATA=1
CREATE_BACKUP=1
YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/uninstall-systemd-service.sh [--purge] [--no-backup] [--yes]

Safely removes the VeloxHash systemd installation.

Default behavior:
  - creates a backup first when veloxhash-backup is available
  - stops and disables veloxhash.service
  - removes installed VeloxHash commands, runner, service unit, and logrotate config
  - keeps /etc/veloxhash, /var/lib/veloxhash, /var/log/veloxhash, and /var/backups/veloxhash

Options:
  --purge      Also remove config, state, logs, backups, and the veloxhash user
  --no-backup  Do not create a pre-uninstall backup
  --yes        Do not prompt for confirmation
  -h, --help   Show this help
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run with sudo." >&2
    exit 1
  fi
}

confirm() {
  if [[ "${YES}" -eq 1 ]]; then
    return
  fi

  local prompt="Remove VeloxHash service and installed commands"
  if [[ "${KEEP_DATA}" -eq 0 ]]; then
    prompt="${prompt}, including config/logs/backups"
  else
    prompt="${prompt}, keeping config/logs/backups"
  fi

  printf '%s? [y/N] ' "${prompt}"
  read -r answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
}

make_backup() {
  if [[ "${CREATE_BACKUP}" -ne 1 ]]; then
    return
  fi

  if command -v veloxhash-backup >/dev/null 2>&1; then
    echo "Creating pre-uninstall backup..."
    veloxhash-backup || {
      echo "Backup failed. Re-run with --no-backup only if you accept that risk." >&2
      exit 1
    }
  else
    echo "Backup command not installed; skipping pre-uninstall backup."
  fi
}

stop_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return
  fi

  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl stop veloxhash-policy.timer 2>/dev/null || true
  systemctl stop veloxhash-policy.service 2>/dev/null || true
  systemctl stop veloxhash-cluster-heartbeat.timer 2>/dev/null || true
  systemctl stop veloxhash-cluster-heartbeat.service 2>/dev/null || true
  systemctl stop veloxhash-cluster-primary.service 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable veloxhash-policy.timer 2>/dev/null || true
  systemctl disable veloxhash-cluster-heartbeat.timer 2>/dev/null || true
  systemctl disable veloxhash-cluster-primary.service 2>/dev/null || true
}

remove_installed_files() {
  rm -f \
    /etc/systemd/system/veloxhash.service \
    /etc/systemd/system/veloxhash-policy.service \
    /etc/systemd/system/veloxhash-policy.timer \
    /etc/systemd/system/veloxhash-cluster-primary.service \
    /etc/systemd/system/veloxhash-cluster-heartbeat.service \
    /etc/systemd/system/veloxhash-cluster-heartbeat.timer \
    /etc/logrotate.d/veloxhash \
    /usr/local/bin/veloxhash \
    /usr/local/bin/veloxhash-mining \
    /usr/local/bin/veloxhash-policy \
    /usr/local/bin/veloxhash-cluster \
    /usr/local/bin/veloxhash-doctor \
    /usr/local/bin/veloxhash-status \
    /usr/local/bin/veloxhash-validate \
    /usr/local/bin/veloxhash-backup \
    /usr/local/bin/veloxhash-restore \
    /usr/local/bin/veloxhash-upgrade \
    /usr/local/bin/veloxhash-uninstall

  rm -rf /usr/local/lib/veloxhash

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true
  fi
}

purge_data() {
  if [[ "${KEEP_DATA}" -eq 1 ]]; then
    return
  fi

  rm -rf \
    /etc/veloxhash \
    /var/lib/veloxhash \
    /var/log/veloxhash \
    /var/backups/veloxhash

  if id -u veloxhash >/dev/null 2>&1; then
    userdel veloxhash 2>/dev/null || true
  fi
}

print_result() {
  echo "VeloxHash systemd installation removed."

  if [[ "${KEEP_DATA}" -eq 1 ]]; then
    cat <<'EOF'

Kept data:
  /etc/veloxhash
  /var/lib/veloxhash
  /var/log/veloxhash
  /var/backups/veloxhash

Reinstall with:
  sudo ./scripts/install-systemd-service.sh
EOF
  else
    echo "Config, state, logs, backups, and service user were removed because --purge was used."
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge)
        KEEP_DATA=0
        ;;
      --no-backup)
        CREATE_BACKUP=0
        ;;
      --yes)
        YES=1
        ;;
      -h|--help|help)
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

  require_root
  confirm
  make_backup
  stop_service
  remove_installed_files
  purge_data
  print_result
}

main "$@"
