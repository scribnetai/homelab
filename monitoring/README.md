# Monitoring — fleet monitoring-tools VM

A small dedicated VM that hosts the lab's monitoring *viewers*:
dashboards and tooling that watch the fleet, starting with **PeaNUT**,
the web dashboard for the NUT server (UPS monitoring). The tools run
as Docker Compose stacks inside one Terraform-managed VM; the VM is
the durable unit, the containers are payloads.

## Design (decided 2026-11-06)

- **A dedicated VM, on purpose.** PeaNUT could have lived on the
  Hermes VM (Docker already there) or in the k3s cluster (the
  fleet-standard pattern). The owner's call: monitoring gets its own
  home, because more monitoring tools are expected to join it, and a
  viewer of the fleet shouldn't share fate with an agent host or
  with the cluster it may need to watch fail.
- **Host: proxmox2.** It holds the fleet's RAM headroom — and it is
  the NUT server's own host (the rack UPS is USB-attached to it and
  its `upsd` serves the LAN). The watcher lives with the watched.
- **Small on purpose.** 2 vCPU / 4 GB / 32 GB. Dashboards are light;
  grow the numbers in `terraform/main.tf` locals when a tenant
  earns it.
- **Exposure: tailnet-only.** Each stack binds to the VM's localhost;
  Tailscale Serve on the VM provides the HTTPS doors (PeaNUT:
  `https://monitoring.<tailnet-name>:8447`). Nothing is published to
  the LAN by the stacks, and nothing is exposed publicly, ever.
- **Its own DNS stays boring.** The VM's resolver is an upstream
  (1.1.1.1), and its Tailscale joins with `--accept-dns=false`: a
  monitoring box must keep resolving while the LAN's DNS is the
  patient.
- **Backup.** The Proxmox Backup Server nightly job covers ALL VMs,
  so this disk lands on the PBS datastore every night.

## Layout

- `terraform/` — the VM (bpg/proxmox, the fleet module pattern:
  clone the node's own Ubuntu 24.04 template, cloud-init installs
  qemu-guest-agent + Docker + Tailscale).
- `docker-compose.yml` — the PeaNUT stack (first tenant), written
  for this lab; see the header in the file.
- `.env.example` — copy to `.env` ON THE VM. The filled `.env`
  never enters git.

## Preflight gates (do not skip)

1. **VMID freedom, cluster-wide.** On any PVE host:
   `ls /etc/pve/nodes/*/qemu-server/114.conf /etc/pve/nodes/*/lxc/114.conf`
   must find nothing. (`qm config` on one node reads only that
   node's folder — the pihole build learned this the hard way.)
2. **Both provider auth legs, one window.** The API token covers API
   calls; the snippet upload rides the provider's separate SSH leg
   (`PROXMOX_VE_SSH_USERNAME` / `PROXMOX_VE_SSH_PASSWORD`). `plan`
   never exercises the SSH leg — only `apply` reveals it missing.
   Set every `PROXMOX_VE_*` variable in the SAME PowerShell window
   that runs terraform; session env vars die with the window.
3. **tfvars gate.** After copying `terraform.tfvars.example` to
   `terraform.tfvars` and filling real values:
   `Select-String -Path .\terraform.tfvars -Pattern '192\.0\.2\.'`
   must return NOTHING.

## Deploy

On the Windows dev PC, in the local clone of this repo:

```
cd monitoring\terraform
copy terraform.tfvars.example terraform.tfvars   # fill real values
# set the PROXMOX_VE_* env vars (see gate 2) in this same window
terraform init
terraform plan      # expect: 1 file (snippet) + 1 VM to add, on proxmox2
terraform apply
```

Then on the VM (SSH in as the cloud-init user):

```
sudo tailscale up --accept-dns=false     # once, by hand -- no auth keys in git
mkdir -p ~/monitoring && cd ~/monitoring
# copy docker-compose.yml + .env.example here from the repo clone, then:
cp .env.example .env                     # set the real NUT_HOST
docker compose up -d
sudo tailscale serve --bg --https=8447 http://127.0.0.1:8080
```

Open `https://monitoring.<tailnet-name>:8447`, create PeaNUT's admin
account (first-run prompt, in the browser — the password goes to
your password manager, nowhere else), and confirm the UPS card shows
live data. If the UPS isn't listed yet: Settings → add the NUT server
(the same host/port as `.env`), no username/password.

## Verify

- `docker ps` on the VM: `peanut` Up, bound to 127.0.0.1:8080 only.
- `tailscale serve status` shows the :8447 door.
- Dashboard values match `upsc <ups>@<nut-host>` run anywhere on the
  LAN (charge, load, runtime).
- Beszel agent + an Uptime Kuma monitor for the door are the usual
  fleet enrollment steps; do them when the VM settles.

## Notes

- **Provider lockfile:** after the first `terraform init`, commit
  `terraform/.terraform.lock.hcl` (the immich precedent — its
  lockfile landed in a follow-up commit once the deployment was
  live).
- **Future tenants** land as additional Compose services (or sibling
  stacks) on this VM. PeaNUT's Prometheus endpoint (`/api/v1/metrics`)
  is the Grafana scrape target when the second visualization layer
  is wanted.
- **NUT Phase 2** (fleet shutdown orchestration) will mint real
  `upsd` users; when it does, PeaNUT gets the monitoring user and
  this README's compose header gets updated in the same pass.
