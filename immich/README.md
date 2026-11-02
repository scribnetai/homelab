# Immich — photo archive VM

Self-hosted photo library (the Techno Tim backlog's Wave 3 item): phone
auto-upload, face/object search, and one home for the photo archive that
used to be scattered across a laptop library and a decade of backup
folders. Immich runs as a Docker Compose stack inside one Terraform-
managed VM; the VM is the durable unit, the containers are a payload.

## Design (decided 2026-11-01)

- **Host: proxmox3.** It holds the fleet's 1 TB local drive, and the
  library is the one workload here that wants exactly that. The host
  is otherwise the lightest of the three.
- **Not Kubernetes.** Longhorn node disks are small and store every
  byte three times; an archive wants one big simple disk close to the
  service. Home services run on Compose here (the build pattern this
  lab adopted from Techno Tim); orchestrated workloads run in k3s.
- **Two disks.** `scsi0` 32 GB (OS + Docker) and `scsi1` 600 GB mounted
  at `/data`, holding BOTH the library (`/data/library`) and the
  database (`/data/postgres`) — one mount, one backup unit. The disk
  grows online (`qm resize`) when the archive earns it.
- **This VM is THE copy — on purpose.** The standing rule used to be
  "Immich is a view, the plain files are the archive." The owner's
  call (2026-11-01): with the Proxmox Backup Server nightly covering
  ALL VMs, the Immich disk lands on the PBS datastore every night,
  which is backup enough to make Immich the primary home. The honest
  gap that leaves: PBS is in the same house — the S3 offsite leg
  (`pbs/README.md` step 11, deferred one week on 2026-11-01) is what
  closes it. Until then, "backed up nightly" is true and "survives
  the house" is not yet.
- **Exposure: tailnet-only.** Tailscale Serve on the VM provides the
  HTTPS door: `https://immich.<tailnet-name>` (Serve terminates TLS
  on 443 and forwards to the app's port 2283). No port is
  published to the LAN by the stack beyond the VM's own address, and
  nothing is exposed publicly, ever. Phone apps point at the Serve
  URL and upload over the tailnet from anywhere.

## Layout

- `terraform/` — the VM (bpg/proxmox, the fleet module pattern:
  clone the node's own Ubuntu 24.04 template, cloud-init installs
  qemu-guest-agent + Docker + Tailscale).
- `docker-compose.yml` — upstream Immich's compose, unmodified (see
  the provenance header in the file). Upgrades take the compose from
  the current release download, never from main.
- `.env.example` — copy to `.env` ON THE VM. The filled `.env` (with
  the real DB password) never enters git.

## Preflight gates (do not skip)

1. **VMID 113 free, cluster-wide:**
   `ls /etc/pve/nodes/*/qemu-server/113.conf /etc/pve/nodes/*/lxc/113.conf`
   on any host must find NOTHING. (`qm config` on one node is not a
   freedom check — that lesson is in the pihole README.)
2. **Template 9002 exists on proxmox3** (clones happen on the target
   node with local storage): `qm list | grep 9002` in proxmox3's shell.
3. **Room on proxmox3's local-lvm:** 32 + 600 GB plus headroom —
   `pvesm status` on proxmox3; expect well over 650 GB available (the
   1 TB drive also carries the k3s agent's disk).
4. **The static IP (.28, last octet of `immich_ip` in your tfvars) is
   unanswered:** `ping` it from the PC — no reply is the pass.

## Deploy

1. **Terraform** (gaming PC, one PowerShell window for ALL of it —
   session env vars die with the window):
   - `cd` to your clone's `immich/terraform`; copy
     `terraform.tfvars.example` to `terraform.tfvars`; fill in real
     values; run the doc-range gate from the example file's header
     (Select-String must find no `192.0.2.`).
   - Set `PROXMOX_VE_API_TOKEN` + `PROXMOX_VE_SSH_*` via the
     Read-Host -AsSecureString pattern (never a plain assignment).
   - `terraform init` → commit the module's `.terraform.lock.hcl`
     afterwards, like the other modules.
   - `terraform plan` → read it: one VM, node proxmox3, two disks.
   - `terraform apply`.
2. **First boot:** cloud-init needs a few minutes (package update +
   Docker + Tailscale). SSH in as your cloud-init user; checkers:
   `docker --version`, `docker compose version`,
   `systemctl is-active docker` → all present/active.
3. **Tailscale ritual** (the fleet standard, expansion book): plain
   `sudo tailscale up` — never `--ssh`; approve in the admin console;
   `sudo tailscale set --ssh=false`; **verify CorpDNS**:
   `tailscale debug prefs | grep -i corpdns` must read true — if
   false, `sudo tailscale set --accept-dns=true` and prove it with
   `getent hosts homelab-vps.<tailnet-name>` returning the 100.x
   address (fleet Key Command 32; three services died silently of
   this on 2026-11-01).
4. **Data disk** (one-time, by hand — Terraform creates disks, it does
   not own filesystems):
   - Identify it: `lsblk` → the 600 GB disk (expect `/dev/sdb`).
   - `sudo mkfs.ext4 /dev/sdb` (the WHOLE disk, no partition table
     needed) — **triple-check the device name against `lsblk` first;
     the 32 GB OS disk is the other one.**
   - `sudo mkdir -p /data`
   - Add to `/etc/fstab` by UUID (`sudo blkid /dev/sdb`):
     `UUID=<uuid> /data ext4 defaults 0 2`
   - `sudo mount -a` → checker: `df -h /data` shows ~590 GB.
   - `sudo mkdir -p /data/library /data/postgres`
5. **The stack:**
   - `mkdir -p ~/immich && cd ~/immich`; fetch `docker-compose.yml`
     from this repo (curl the raw file — and sha256-gate any re-fetch,
     like the fleet update checker) and create `.env` from
     `.env.example`: real `DB_PASSWORD` (alphanumeric only, generated,
     straight into the password manager), `IMMICH_VERSION` pinned to
     the exact current release.
   - `docker compose up -d` → checkers: `docker compose ps` (all four
     containers up/healthy), `curl -s localhost:2283/api/server/ping`
     → `{"res": "pong"}`.
6. **The door:** `sudo tailscale serve --bg 2283` → checker:
   `tailscale serve status` shows the 443 → 2283 mapping. Open
   `https://immich.<tailnet-name>` — create the admin account
   (password into the password manager in the same breath).
7. **Enroll in monitoring** like every other host: Beszel agent +
   Uptime Kuma monitors (tailnet targets ONLY — Kuma cannot reach
   LAN addresses; that rule is fleet Key Command material).

## First-week checks

- **Tonight's PBS run must include VM 113.** The job is set to ALL
  VMs, so it should — verify in the morning-after Content view
  (a fixed VM list is exactly how the pihole VM got missed on
  2026-11-01; trust, then verify).
- **Phone apps:** install Immich on the phones, server URL = the
  Serve door, enable background upload on Wi-Fi. First sync is the
  real ingest test.
- **Bulk import is phase 2, deliberately:** the historical folders
  (laptop library, the old backup drives) get consolidated as a
  separate, checksummed pass — not by dragging them in during the
  install high. Plan it from the archive inventory, not from vibes.

## Pitfalls already paid for (elsewhere in this repo)

- A green `terraform plan` does not prove endpoint or auth (pbs
  module) — check tfvars values explicitly at plan review.
- The provider has TWO auth legs; plan never exercises the SSH leg
  (k3s module) — apply is where a missing leg surfaces, so have both
  set in the same window before you start.
- New-host Tailscale without the CorpDNS check ships a node that
  cannot resolve any tailnet name (2026-11-01, three times) — step 3
  of the deploy is not decoration.
- Kuma monitors aimed at LAN IPs are red BY DESIGN (the VPS has no
  route to the LAN) — enroll new monitors with tailnet targets.
