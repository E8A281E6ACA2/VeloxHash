# VeloxHash

VeloxHash is a CPU-focused miner service with a built-in web dashboard and a stable Ubuntu systemd deployment mode.

## Current Features

- CPU mining support
- Optional OpenCL and CUDA backends
- Default donation level set to `0`
- Built-in web dashboard at the HTTP API root path with pause/resume controls
- Smart systemd mode: dashboard/API starts at boot, CPU mining is controlled by an automatic idle-hours policy
- Physical-host deployment with backup, restore, validation, status, and upgrade tools
- Project binary target renamed to `veloxhash`

## Web Dashboard

Enable the HTTP API and open:

```text
http://<server-ip>:8089/
```

The dashboard reads `/1/summary`, shows per-thread hashrate from the summary payload, and can call `/json_rpc` for pause/resume/stop when the service is started with an API token and unrestricted HTTP API mode.

See [docs/WEB_DASHBOARD.md](docs/WEB_DASHBOARD.md) for details.

## Build

Supported physical-host targets:

- Ubuntu/Debian `x86_64` / `amd64`
- Ubuntu/Debian `aarch64` / `arm64`

```bash
cmake -S . -B build-veloxhash -DCMAKE_BUILD_TYPE=Release -DWITH_OPENCL=OFF -DWITH_CUDA=OFF
cmake --build build-veloxhash -j$(nproc)
./build-veloxhash/veloxhash --version
```

On Ubuntu/Debian, install the baseline build dependencies first:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev
```

## systemd

Cache-based Bash install. The source tree is kept under
`~/.cache/veloxhash/source`; installed service files still use normal system
paths such as `/etc/veloxhash`, `/usr/local/bin`, and `/var/log/veloxhash`.

Run as `root` to install the system service. Run as a normal user to install
user mode under `~/.cache/veloxhash/runtime`; user mode does not write to
`/etc` or `/usr/local/bin`.

```bash
sudo apt-get update
sudo apt-get install -y git curl
mkdir -p ~/.cache/veloxhash
if [ -d ~/.cache/veloxhash/source/.git ]; then
  git -C ~/.cache/veloxhash/source pull --ff-only
else
  git clone https://github.com/E8A281E6ACA2/VeloxHash.git ~/.cache/veloxhash/source
fi
bash ~/.cache/veloxhash/source/scripts/bootstrap-cache-install.sh <public-wallet-address>
```

For private repositories, configure GitHub access on the host before cloning.
If the repository is made public, `scripts/bootstrap-cache-install.sh` can also
be executed through a raw `curl | bash` flow.

Mode selection:

```bash
# Automatic: root -> system mode, normal user -> user mode
bash ~/.cache/veloxhash/source/scripts/bootstrap-cache-install.sh <public-wallet-address>

# Force system service when the user has sudo
bash ~/.cache/veloxhash/source/scripts/bootstrap-cache-install.sh --mode system <public-wallet-address>

# Force user mode without sudo
bash ~/.cache/veloxhash/source/scripts/bootstrap-cache-install.sh --mode user <public-wallet-address>
```

User-mode commands:

```bash
~/.cache/veloxhash/runtime/bin/veloxhash-user status
~/.cache/veloxhash/runtime/bin/veloxhash-user token
~/.cache/veloxhash/runtime/bin/veloxhash-user stop
~/.cache/veloxhash/runtime/bin/veloxhash-user start
```

Clone and start manually:

```bash
git clone https://github.com/E8A281E6ACA2/VeloxHash.git
cd VeloxHash
sudo ./start-mining.sh <public-wallet-address>
```

The same script works on `amd64` and `arm64` Ubuntu/Debian hosts. It builds the
binary locally for the current CPU architecture, installs the systemd service,
enables boot startup, starts the dashboard/API, and configures the wallet when
one is provided.

For a durable Ubuntu service on `0.0.0.0:8089`:

```bash
sudo ./scripts/install-systemd-service.sh
sudo veloxhash-mining wallet set <public-wallet-address>
sudo sed -n 's/^VELOXHASH_API_TOKEN=//p' /etc/veloxhash/veloxhash.env
sudo systemctl status veloxhash
```

One-command physical-host install from the source tree:

```bash
sudo ./start-mining.sh <public-wallet-address>
```

The installer copies the current `build-veloxhash/veloxhash` binary to `/usr/local/bin/veloxhash`, installs `/etc/veloxhash/config.json`, generates a random API token in `/etc/veloxhash/veloxhash.env`, enables boot startup, starts the service, enables the automatic policy timer, and runs health checks.

The service starts at boot. The dashboard/API stays online at `8089`. CPU mining is controlled by `veloxhash-policy.timer`, which checks every minute. The default policy uses 50% CPU, stops immediately on recent non-service user activity, does not mine during `08:00-22:00`, and stops mining when load1 is above CPU cores * `0.60`.

VeloxHash does not import wallet keys. Use only a public pool payout address; never put a private key or seed phrase in config files. Mining will not start until you configure a public pool payout address:

```bash
sudo veloxhash-mining wallet set <public-wallet-address>
```

Each install writes `/etc/veloxhash/install-info.json` with the install time, source directory, binary version, git revision, port, and service state. The token is not written to this file.

```bash
sudo veloxhash-mining status
sudo veloxhash-mining wallet
sudo veloxhash-mining wallet set <public-wallet-address>
sudo veloxhash-mining wallet clear
sudo veloxhash-mining enable
sudo veloxhash-mining disable
sudo veloxhash-mining token
sudo veloxhash-mining token rotate
sudo veloxhash-policy status
sudo veloxhash-policy enable
sudo veloxhash-policy disable
sudo veloxhash-status
sudo veloxhash-status --short
sudo veloxhash-validate
sudo veloxhash-backup
sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
sudo veloxhash-upgrade
sudo veloxhash-doctor
sudo veloxhash-uninstall
```

The service has restart limiting enabled and writes logs to `/var/log/veloxhash/veloxhash.log`. The installer also adds `/etc/logrotate.d/veloxhash` so logs are rotated automatically. Use `veloxhash-status` for a compact install, service, port, process, API, and recent-log snapshot; run it as root when you want authenticated API details.

Create a rollback archive before risky changes:

```bash
sudo veloxhash-backup
sudo veloxhash-restore /var/backups/veloxhash/<backup>.tar.gz
```

Backups include `/etc/veloxhash`, service files, installed VeloxHash commands, the runner, and a manifest. Restore creates a pre-restore backup first when `veloxhash-backup` is available.

Uninstall keeps config, logs, and backups by default:

```bash
sudo veloxhash-uninstall
sudo veloxhash-uninstall --purge
```

See [docs/OPERATIONS.md](docs/OPERATIONS.md) for the full operations runbook and policy details.

## License Notice

VeloxHash includes GPL-licensed upstream mining code. Original copyright notices are kept in source files where required by the license.
