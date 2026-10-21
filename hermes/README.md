# Hermes Agent — VM deployment

Infrastructure-as-code for the home Hermes Agent deployment: a
from-scratch Docker install on a dedicated VM, reached through
Telegram, the Hermes Desktop app, and the CLI — one data dir behind
all three surfaces.

## Shape

| Service | Command | Role |
| --- | --- | --- |
| `hermes` | `gateway run` | Messaging gateway (Telegram) + cron scheduler |
| `hermes-backend` | `serve --host 0.0.0.0 --port 9119` | Backend for Hermes Desktop / web dashboard |

One compose file, two containers. Both services mount the same
`./data` volume at `/opt/data` — the data dir is the brain
(profiles, sessions, memory, config, secrets); the containers are
disposable. The backend's port is published only on the VM's
Tailscale IP (placeholdered in the committed compose), and a
non-loopback bind requires an auth provider: this deployment uses
dashboard basic auth (username + password hash in the data dir's
`config.yaml`, signing secret in its `.env`). The full
build/operate runbook is maintained privately alongside the agent
personalities.

## Rules

- Secrets live only in `data/.env` (gitignored, chmod 600) — never
  in this repo.
- `data/` is created on the host and never committed (see
  `.gitignore` in this directory).
- The gateway tracks `:stable`; the backend pins the verified
  digest. Update both together, deliberately.
