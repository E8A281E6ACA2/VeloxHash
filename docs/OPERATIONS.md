# VeloxHash Operations

This document is the operational runbook for the Ubuntu systemd deployment.

## Service Model

- Service name: `veloxhash.service`
- Dashboard/API: `http://<server-ip>:8089/` by default. If that port is occupied during installation, VeloxHash automatically chooses the next available port.
- Config: `/etc/veloxhash/config.json`
- Environment/token: `/etc/veloxhash/veloxhash.env`
- Install record: `/etc/veloxhash/install-info.json`
- Logs: `/var/log/veloxhash/veloxhash.log`
- Backups: `/var/backups/veloxhash`
- Optional cluster registry: `http://<primary-ip>:8090/`

The service starts at boot. The dashboard and API stay online. CPU mining is controlled by `veloxhash-policy.timer`.

Default policy:

- CPU target: `50%` via `cpu.max-threads-hint`
- User activity: stop mining when a non-service user was active in the last `15` minutes
- Work window: `08:00-22:00`, no mining
- Off-hours: mining may run when CPU is idle
- Busy threshold: stop mining when load1 is above CPU cores * `0.60`
- Check interval: every minute

## Daily Commands

```bash
sudo veloxhash-status
sudo veloxhash-status --short
sudo veloxhash-status --json
sudo veloxhash-validate
sudo veloxhash-doctor
sudo veloxhash-policy status
sudo veloxhash-cluster status
```

Use `veloxhash-status` first for a fast snapshot. Use `veloxhash-doctor` for a deeper health check.

## Mining Control

```bash
sudo veloxhash-mining status
sudo veloxhash-mining enable
sudo veloxhash-mining disable
sudo veloxhash-mining pool
sudo veloxhash-mining pool set auto.c3pool.org:33333 x monero
```

Manual mining commands still work, but the automatic policy may override them on its next timer run.

Automatic policy:

```bash
sudo veloxhash-policy status
sudo veloxhash-policy enable
sudo veloxhash-policy disable
sudo veloxhash-policy run
```

Policy values live in `/etc/veloxhash/veloxhash.env`:

```text
VELOXHASH_POLICY_ENABLED=1
VELOXHASH_POLICY_CPU_PERCENT=50
VELOXHASH_POLICY_WORK_START=08
VELOXHASH_POLICY_WORK_END=22
VELOXHASH_POLICY_LOAD_THRESHOLD=0.60
VELOXHASH_POLICY_ACTIVE_MINUTES=15
```

`veloxhash-policy disable` stops the timer and restarts VeloxHash with mining disabled. The dashboard/API remains online.

User activity is checked first and is detected from login sessions using `who -u`. The `veloxhash` service user is ignored. Any other user with an idle time within `VELOXHASH_POLICY_ACTIVE_MINUTES` is considered active, so mining stays off.

## API Token

Read the token:

```bash
sudo veloxhash-mining token
```

Rotate the token:

```bash
sudo veloxhash-mining token rotate
```

Token rotation creates a backup when `veloxhash-backup` is installed, updates `/etc/veloxhash/veloxhash.env`, fixes permissions, and restarts the service.

## Cluster Monitoring

Cluster monitoring is installed but disabled by default. It is intentionally separate from the mining core: workers send health heartbeats to one primary node, and the primary only records node count/status. It does not start, stop, or reconfigure mining on other machines.

Nodes are uniquely identified by `VELOXHASH_CLUSTER_NODE_ID`, a random persistent ID stored in `/etc/veloxhash/veloxhash.env`. IP address is recorded for visibility only: workers report local interface IPs, and the primary records the remote source IP it sees. Do not use IP address as the unique worker identity because NAT, DHCP, IPv6 privacy addresses, and cloud rebuilds can change it.

Enable the current machine as the primary registry:

```bash
sudo veloxhash-cluster init-primary
sudo veloxhash-cluster token
sudo veloxhash-cluster nodes
```

The primary registry listens on `0.0.0.0:8090` by default. Share the cluster token only with nodes that should report into this primary.

Join a worker node:

```bash
sudo veloxhash-cluster join --primary-url http://<primary-ip>:8090 --token <cluster-token>
sudo veloxhash-cluster status
```

List nodes from the primary:

```bash
sudo veloxhash-cluster nodes
sudo veloxhash-cluster nodes --json
```

Disable cluster mode on any node:

```bash
sudo veloxhash-cluster leave
```

Cluster settings live in `/etc/veloxhash/veloxhash.env`:

```text
VELOXHASH_CLUSTER_ENABLED=1
VELOXHASH_CLUSTER_ROLE=primary
VELOXHASH_CLUSTER_TOKEN=<cluster-token>
VELOXHASH_CLUSTER_PRIMARY_URL=http://127.0.0.1:8090
VELOXHASH_CLUSTER_PORT=8090
VELOXHASH_CLUSTER_STALE_SECONDS=180
```

## Validation

```bash
sudo veloxhash-validate
```

Validation checks:

- config JSON syntax
- HTTP host and port
- API token presence when binding to `0.0.0.0`
- mining switch value
- optional cluster command and units
- config/env ownership and permissions
- systemd unit, runner, binary, and listener state

## Backup And Restore

Create a backup:

```bash
sudo veloxhash-backup
```

Restore a backup:

```bash
sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
```

Restore creates a pre-restore backup first when possible.

## Upgrade

Upgrade from the current source tree:

```bash
cd /home/yuanhuan/VeloxHash
sudo veloxhash-upgrade
```

Skip build and install the current `build-veloxhash/veloxhash` binary:

```bash
sudo veloxhash-upgrade --skip-build
```

Upgrade creates a backup first, installs the current binary and operational scripts, restarts the service, then runs validation and doctor checks.

## Uninstall

Remove service and installed commands, keeping config/logs/backups:

```bash
sudo veloxhash-uninstall
```

Remove everything including config/logs/backups:

```bash
sudo veloxhash-uninstall --purge
```

## Troubleshooting Flow

1. Check one-line status:

   ```bash
   sudo veloxhash-status --short
   ```

2. Run validation:

   ```bash
   sudo veloxhash-validate
   ```

3. Run doctor:

   ```bash
   sudo veloxhash-doctor
   ```

4. Inspect logs:

   ```bash
   sudo journalctl -u veloxhash -n 100 --no-pager
   sudo tail -n 100 /var/log/veloxhash/veloxhash.log
   ```

5. Restore if needed:

   ```bash
   sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
   ```
