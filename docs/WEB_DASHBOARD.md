# VeloxHash Web Dashboard

VeloxHash now serves a built-in web dashboard from the existing HTTP API server.

## Enable it

Set the HTTP API block in your config file:

```json
"http": {
  "enabled": true,
  "host": "0.0.0.0",
  "port": 8089,
  "access-token": null,
  "restricted": true
}
```

Binding to `0.0.0.0` allows access from other machines. Keep an `access-token` set for any network-exposed instance.

## Open the dashboard

Start VeloxHash with that config, then open:

```text
http://<server-ip>:8089/
```

`8089` is the default port. Installers automatically choose the next available
port if it is occupied. Read the selected port from
`/etc/veloxhash/veloxhash.env` or `veloxhash-status`.

The same page is also available at `/index.html` and `/dashboard`.

If the API requires a token, the page shows a token input. Enter the same value as `http.access-token` or the service token from `/etc/veloxhash/veloxhash.env`. The token is stored in browser local storage for that origin and sent as a Bearer token to API requests.

## Controls

Pause, resume, and stop buttons call `/json_rpc`. These controls require:

- an API token
- unrestricted HTTP API mode (`"restricted": false` or `--http-no-restricted`)

The included systemd service starts VeloxHash with `--http-access-token=${VELOXHASH_API_TOKEN}` and `--http-no-restricted`, so controls are available after entering the generated token.

For systemd installs, the dashboard/API stays online and CPU mining is controlled by the automatic policy. Use:

```bash
sudo veloxhash-mining enable
sudo veloxhash-mining disable
sudo veloxhash-policy status
```

The dashboard pause/resume buttons control an already-running miner. The `veloxhash-policy` timer may later enable or disable mining based on time, CPU load, and recent user activity.

Use `sudo veloxhash-doctor` to check service state, port binding, token-protected API access, and backend status from the server.

Cluster node counts are managed by the optional `veloxhash-cluster` command, not by the embedded dashboard. This keeps the mining dashboard simple and keeps cluster monitoring outside the mining core.

## What it shows

- Current, average, 15-minute, and highest hashrate
- Accepted and total shares
- Pool, ping, failures, and uptime
- Miner version, CPU, feature flags, load, and memory
- Per-thread hashrate bars
- Pause/resume status and guarded control buttons
- Recent API connection/result errors

The dashboard is embedded in the binary and does not require Node.js, npm, external assets, or a separate web server.
