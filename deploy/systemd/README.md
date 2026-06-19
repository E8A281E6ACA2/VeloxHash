# VeloxHash systemd deployment

This directory contains the service template used by `scripts/install-systemd-service.sh`.

The installed service:

- runs `/usr/local/bin/veloxhash`
- reads `/etc/veloxhash/config.json`
- binds the dashboard/API to `0.0.0.0:8089`
- stores the API token in `/etc/veloxhash/veloxhash.env`
- records deployment metadata in `/etc/veloxhash/install-info.json`
- enables unrestricted HTTP API mode only with the token supplied by systemd
- starts the dashboard/API at boot and lets `veloxhash-policy.timer` control CPU mining
- defaults to 50% CPU, no mining when a non-service user was active in the last 15 minutes, no mining during `08:00-22:00`, and no mining when load1 is above CPU cores * `0.60`
- checks the automatic mining policy every minute
- installs optional cluster monitoring, disabled until `veloxhash-cluster init-primary` or `veloxhash-cluster join` is run
- limits restart storms with `StartLimitBurst=5` in 5 minutes
- rotates `/var/log/veloxhash/*.log` via `/etc/logrotate.d/veloxhash`

Install after building:

```bash
cmake --build build-veloxhash -j$(nproc)
sudo ./scripts/install-systemd-service.sh
```

Useful commands:

```bash
sudo systemctl status veloxhash
sudo journalctl -u veloxhash -n 100 --no-pager
sudo systemctl restart veloxhash
sudo logrotate -d /etc/logrotate.d/veloxhash
sudo veloxhash-mining status
sudo veloxhash-mining enable
sudo veloxhash-mining disable
sudo veloxhash-mining token rotate
sudo veloxhash-policy status
sudo veloxhash-policy enable
sudo veloxhash-policy disable
sudo veloxhash-status
sudo veloxhash-status --short
sudo veloxhash-cluster status
sudo veloxhash-cluster nodes
sudo veloxhash-validate
sudo veloxhash-backup
sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
sudo veloxhash-upgrade
sudo veloxhash-uninstall
sudo veloxhash-doctor
```
