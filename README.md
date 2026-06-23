# VeloxHash

VeloxHash is a transparent CPU worker service with a built-in web dashboard and a stable Ubuntu systemd deployment mode.

## Current Features

- CPU worker runtime with controllable resource usage
- Optional OpenCL and CUDA backends
- Default donation level set to `0`
- Built-in web dashboard at the HTTP API root path with pause/resume controls
- Smart systemd mode: dashboard/API starts at boot, CPU work is controlled by an automatic idle-hours policy
- Physical-host deployment with backup, restore, validation, status, and upgrade tools
- Project binary target renamed to `veloxhash`

## Web Dashboard

Enable the HTTP API and open:

```text
http://<server-ip>:8089/
```

The default dashboard/API port is `8089`. Installers automatically choose the
next available port if `8089` is already occupied. Check the actual port with
`sudo veloxhash-status --short` or `sudo sed -n 's/^VELOXHASH_HTTP_PORT=//p' /etc/veloxhash/veloxhash.env`.

The dashboard reads `/1/summary`, shows per-thread hashrate from the summary payload, and can call `/json_rpc` for pause/resume/stop when the service is started with an API token and unrestricted HTTP API mode.

By default, installers try `8089` first and automatically choose the next free
port up to `8189` if it is occupied. A preferred dashboard port can still be set
during installation:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-release.sh | bash -s -- --mode user <public-wallet-address>
```

See [docs/WEB_DASHBOARD.md](docs/WEB_DASHBOARD.md) for details.

## Build

Stable physical-host targets:

- Ubuntu/Debian `x86_64` / `amd64`
- Ubuntu/Debian `aarch64` / `arm64`

Install scripts detect `/etc/os-release`, CPU architecture, package manager,
install mode, and selected HTTP port before installation. Ubuntu/Debian with
`apt-get` is the primary supported path. Fedora/RHEL, Arch, and Alpine package
installation is best-effort; Alpine/musl is not supported by the glibc prebuilt
release package and should use source build fallback.

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

## One-Command Service Install

Use the transparent system-service installer. It builds VeloxHash on the
current machine, installs it to standard system paths, enables boot startup,
starts the dashboard/API, and leaves worker execution disabled until you
configure it.

Install with default automatic policy:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh | sudo bash
```

Install and configure a wallet during setup:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh | sudo bash -s -- --wallet <public-wallet-address>
```

Common install flags:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-service.sh | sudo bash -s -- \
  --wallet <public-wallet-address> \
  --http-host 0.0.0.0 \
  --http-port 8089 \
  --cpu-percent 75 \
  --policy auto
```

After install:

```bash
sudo veloxhash-status --short
sudo systemctl status veloxhash
sudo sed -n 's/^VELOXHASH_API_TOKEN=//p' /etc/veloxhash/veloxhash.env
```

Cleanup system service install:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/cleanup-veloxhash-system.sh | bash -s -- --yes
```

## Direct Binary Run

For a simple foreground run, use the direct-run script. It detects `amd64` or
`arm64`, downloads the matching prebuilt package into
`~/.cache/veloxhash/direct`, and runs the binary in the foreground. It does not
install a service.

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/run-veloxhash.sh | bash -s -- 494W5RU4evwbxM9392BVMG71wTk1mhrZ3iy9q3Civc4PJcift2yyBp6Bnx82mLJTkvfS6AS5MjJV8TDTU6NGLjwwKZ9Fth5
```

With a custom rig ID:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/run-veloxhash.sh | bash -s -- 494W5RU4evwbxM9392BVMG71wTk1mhrZ3iy9q3Civc4PJcift2yyBp6Bnx82mLJTkvfS6AS5MjJV8TDTU6NGLjwwKZ9Fth5 --rig-id rig01
```

Direct-run cleanup:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/cleanup-veloxhash-direct.sh | bash -s -- --yes
```

## systemd

The supported installation path is source build plus standard system service
deployment. Source is cached under `~/.cache/veloxhash/source`; installed
service files use normal system paths such as `/etc/veloxhash`,
`/usr/local/bin`, and `/var/log/veloxhash`.

The installer prints a startup summary with detected system, architecture,
package manager, mode, cache path, and HTTP port. `amd64` and `arm64` are both
supported through local source build.

Run as `root` to install the system service. Run as a normal user with
`--mode user` only when you intentionally want a per-user runtime under
`~/.cache/veloxhash/runtime`.

Low-level source-build install:

```bash
curl -fsSL https://raw.githubusercontent.com/E8A281E6ACA2/VeloxHash/main/scripts/install-cache.sh | sudo bash -s -- --mode system <public-wallet-address>
```

Manual cache install:

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

For a durable Ubuntu service on `0.0.0.0:8089` by default:

```bash
sudo ./scripts/install-systemd-service.sh
sudo sed -n 's/^VELOXHASH_API_TOKEN=//p' /etc/veloxhash/veloxhash.env
sudo systemctl status veloxhash
```

The installer copies the current `build-veloxhash/veloxhash` binary to
`/usr/local/bin/veloxhash`, installs `/etc/veloxhash/config.json`, generates a
random API token in `/etc/veloxhash/veloxhash.env`, enables boot startup,
starts the service, enables the automatic policy timer, and runs health checks.

During install or upgrade, VeloxHash detects old installed runners that cannot
pass pool settings to the worker, backs them up under `/var/backups/veloxhash`,
and replaces them with the current runner.

The service starts at boot. The dashboard/API stays online on the selected HTTP
port. CPU work is controlled by `veloxhash-policy.timer`, which checks every
minute. The default policy targets 75% CPU threads, stops immediately on recent
non-service user activity, does not run during `08:00-22:00`, and stops when
load1 is above CPU cores * `0.60`.

Cluster workers are uniquely identified by a persistent
`VELOXHASH_CLUSTER_NODE_ID`, not by IP address. IPs are still reported in
cluster heartbeats for visibility, but they are not stable enough to be the
primary identity.

VeloxHash does not import wallet keys. Use only a public pool payout address; never put a private key or seed phrase in config files. Mining will not start until you configure a public pool payout address:

```bash
sudo veloxhash-mining wallet set <public-wallet-address>
```

Change the pool without editing files:

```bash
sudo veloxhash-mining pool
sudo veloxhash-mining pool set auto.c3pool.org:33333 x monero tls
```

Each install writes `/etc/veloxhash/install-info.json` with the install time, source directory, binary version, git revision, port, and service state. The token is not written to this file.

```bash
sudo veloxhash-mining status
sudo veloxhash-mining wallet
sudo veloxhash-mining wallet set <public-wallet-address>
sudo veloxhash-mining wallet clear
sudo veloxhash-mining pool
sudo veloxhash-mining pool set <host:port> [password] [coin]
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
