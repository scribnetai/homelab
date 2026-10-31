# Proxmox Backup Server — fleet backups (D8)

The lab's backup system: **Proxmox Backup Server 4.2** (free, AGPL) as the
`proxmox-backup` VM (VMID 101) on the `proxmox` host, built 2026-10-31.
Terraform module: [`terraform/`](terraform/).

## Design

- **Datastore on a passed-through drive.** The host's USB backup drive
  (5 TB) is passed through *whole* to this VM and formatted inside PBS —
  deliberately not a virtual disk. A PBS datastore is a self-describing
  directory tree (content-addressed chunks + snapshot indexes, VM configs
  inside the snapshots), so the drive alone restores the fleet onto fresh
  hardware — even a single new PVE node with a fresh PBS pointed at the
  existing datastore. Portability was the deciding requirement.
- **All three hosts back up over the network** to this one PBS (PVE
  storage type "Proxmox Backup Server", scoped API token). One backup
  job covers every VM; dedup + incremental-forever make nightly restore
  points cost only their changed chunks.
- **CPU `x86-64-v2-AES`** (fleet standard, D7): restorable anywhere.
- **Not covered, by design (yet):** drive death / house-level loss (the
  drive is still a single copy — offsite sync is a later phase; PBS 4.2
  supports S3 datastores and sync jobs), and the PVE cluster config
  itself (`/etc/pve` — the repos carry those definitions).

## Build sequence (2026-10-31)

1. [x] ISO onto the host's ISO storage, **sha256 verified** against
   Proxmox's published sum before use. (Note: `download.proxmox.com`
   presented a mismatched TLS cert from the host that day; the ISO came
   via the PC + GUI upload instead — the checksum is the gate either way.)
2. [x] VM created by Terraform (`terraform/`), installer ISO attached.
3. [ ] OS install (interactive wizard): 32 GB disk, America/New_York,
   root password to the password manager, hostname
   `proxmox-backup.home.arpa`, static IP (the fleet's backup slot — .24,
   mirroring the future 10.10.20.24), gateway/DNS = the LAN gateway.
4. [ ] **Update workflow, before anything else runs on it** (standing
   rule — a new machine joins patched, same as the k3s nodes):
   swap the default enterprise repo for `pbs-no-subscription`
   (PBS GUI → Repositories, or the deb822 sources), then the fleet
   checker, fingerprint-verified as always:
   `bash /tmp/check-updates.sh --apply` (see `updates/README.md`).
   Take any required reboot in this window — the node serves nothing yet.
5. [ ] Detach the installer ISO: remove the `cdrom` block in
   `terraform/main.tf`, plan, apply (the whole block is temporary by
   design; it takes the deprecated `enabled` attribute out with it).
6. [ ] USB passthrough of the backup drive (`qm set` on the host — the
   provider has no USB block; record the device id used), format inside
   PBS, create the datastore on it.
7. [ ] PBS user + API token scoped to the datastore (backup role only);
   credentials to the password manager, never to git/chat/ledger.
8. [ ] Add PBS as storage on the PVE cluster; one backup job for all
   VMs, nightly, with prune/GC retention (daily 14 / weekly 8 /
   monthly 6 as the starting policy) and a scheduled **verify job**.
9. [ ] **Proof before trust:** one manual backup + a test restore to a
   scratch VMID, verified booting, then deleted.
10. [ ] Enroll in monitoring: Beszel agent + Uptime Kuma monitors, like
    every other host. Tailscale + LE cert for the UI door, tailnet-only,
    same as the PVE hosts.

## Pitfalls already paid for (2026-10-31)

- A fresh module needs `versions.tf` (required_providers `bpg/proxmox`);
  without it `terraform init` resolves the nonexistent `hashicorp/proxmox`.
- **A green `terraform plan` does not prove endpoint or auth** — for a
  from-scratch create the provider never dials the API until apply. The
  first apply failed on the example tfvars' doc-range endpoint
  (192.0.2.10) for exactly this reason. Check tfvars values explicitly
  at plan review.
- The cdrom `enabled` attribute is deprecated/no-op in provider 0.117 —
  `file_id` governs media. (The whole cdrom block leaves at step 5.)
- Commit each module's `.terraform.lock.hcl` after its first init, like
  the k3s module does.
