# Homelab

Infrastructure-as-code for the homelab rebuild. Every service is defined as code —
nothing hand-configured — so the whole cloud side can move providers in ~15 minutes.

Companion doc: the **Homelab Runbook** (living document — inventory, topology,
addressing plan, bring-up checklists, YouTube ideas). Code lives here; narrative lives there.

## Layout

- `vps/cloud-init.yaml` — first-boot bootstrap for the cloud VM (Ubuntu 24.04, Docker,
  Tailscale, ufw, automatic security updates). Portable: Hetzner, AWS, Azure and
  DigitalOcean all accept cloud-init user data.
- `vps/docker-compose.yml` — cloud services. Today: Uptime Kuma (uptime monitoring +
  status page + alerts). Bound to localhost; exposed on the tailnet via
  `tailscale serve` (see Security notes).
- `vps/backup.sh` / `vps/restore.sh` — tarball backup and restore for the Kuma data volume.
- `k8s/` — Kubernetes learning track: k3s on the Proxmox NUCs, coupled with the
  VPS setup (one repo, two runtimes). See `k8s/README.md`.
- `CHANGELOG.md` — what changed, when.

## Quickstart: the VPS (Hetzner)

1. Make sure you have an SSH key on your PC. If not:
   - Windows (PowerShell): `ssh-keygen -t ed25519`
   - Print the public key: `Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub`
2. Hetzner Cloud console → new project → **Add server**:
   - Location: **Ashburn, VA**
   - Image: **Ubuntu 24.04**
   - Type: **Shared Resources → Regular Performance → CPX12** (~$13.49/mo)
   - Networking: defaults
   - SSH keys: add your public key
   - Cloud-init: paste the full contents of `vps/cloud-init.yaml`
     (put your SSH public key in the `TODO` slot first)
   - Name: `homelab-vps` → **Create**
3. `ssh techops@<server-ip>`
4. `sudo tailscale up` — approve the SSO login in your browser.
5. `sudo tailscale serve --bg http://127.0.0.1:3001` — publishes Kuma on your tailnet
   with automatic HTTPS. Verify with `tailscale serve status`.
6. `git clone https://github.com/scribnetai/homelab.git && cd homelab/vps && docker compose up -d`
7. From your phone or PC (on the tailnet): `https://homelab-vps.<your-tailnet>.ts.net`
   (find your tailnet name with `tailscale status`) → create the Kuma admin account.
   Start adding monitors.

## Security notes

- Kuma binds to `127.0.0.1` only. Docker programs iptables directly and **bypasses ufw**,
  so publishing the port normally would expose it to the public internet despite the
  host firewall. `tailscale serve` is what puts it on the tailnet (with HTTPS) —
  nothing ever listens publicly.
- Defense in depth: in the Hetzner console, attach a firewall allowing inbound
  `22/tcp` only. On other providers, translate to their equivalent.

## Backup & restore

- Back up: run `./backup.sh` in `vps/` on the server, then `scp` the tarball from
  `backups/` somewhere safe.
- Restore (fresh server, same repo): `docker compose up -d` once, then
  `./restore.sh backups/<file>.tgz`.

## Moving providers

The VPS is disposable by design. `cloud-init.yaml` builds the box on any cloud that
takes user data; `docker-compose.yml` plus the data volume *is* the app.

1. `./backup.sh` on the old box, copy the tarball off.
2. New VM anywhere, same `cloud-init.yaml` pasted as user data.
3. Clone this repo, `./restore.sh backups/<file>.tgz`, `docker compose up -d`.
4. `sudo tailscale up` with the **same node name** — MagicDNS stays stable, then
   re-run the `tailscale serve` command from step 5 above.
5. Update DNS if anything public pointed at the old IP. Done.

## What's next

- Beszel hub on the VPS + agents on lab boxes (per-host metrics).
- Lab-side bring-up: firewalls → switches → Proxmox → Tailscale subnet routing.
- Kubernetes: k3s control plane on NUC-1, worker on NUC-2 — scaffold is in
  `k8s/`, install runs during the Proxmox bring-up.
- Kuma monitors for every lab service as it comes online.
