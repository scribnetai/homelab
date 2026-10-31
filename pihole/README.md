# Pi-hole VM -- build doc

Network-wide DNS ad-blocking (Pi-hole v6) for the home/lab LAN,
inspired by the Techno Tim homelab services tour (adopted backlog,
Wave 2 -- pulled forward and built standalone on the flat LAN; the
re-IP moves it with everything else).

## Shape

| Item | Value |
| --- | --- |
| Form | Proxmox VM from Terraform (`terraform/`), Docker Compose Pi-hole v6 inside (`docker-compose.yml`) |
| Host | NUC-3 (the lightest node; NUC-1 carries the backup stack -- zero contention by design) |
| VMID | 105 (pinned in the module; first choice 103 collided -- see Pitfalls) |
| Size | 2 vCPU `x86-64-v2-AES` / 2 GB RAM / 32 GB on local-lvm -- roaming CPU type (D7): DNS must restore/migrate onto any host |
| Address | The `.27` static in the tfvars (current LAN), which mirrors to the `.27` slot of the future lab VLAN at re-IP -- same trick the PBS VM used with `.24` |
| Template | That node's own Ubuntu 24.04 cloud template copy (per-node templates on local storage) |
| NOT in k3s | DNS lives under the cluster, never inside it -- no circular dependency |

Stage gates:

- **Stage 1 (this build):** VM up, Pi-hole answering, tested from ONE
  device pointed at it by hand. Nothing else changes.
- **Stage 2 (separate decision):** hand Pi-hole's address out as the
  LAN's DNS via router DHCP. Never before Stage 1 is proven -- a
  single unproven instance must not become critical-path for the
  whole house mid-backup-cutover. A second instance + sync (the
  tour's pattern) is the long-term answer to the single-point
  question.

## Build sequence

1. **Preflight (read-only, one node: NUC-3).**
   - Ping the planned `.27` -- expect no reply / 100% loss.
   - VMID freedom, CLUSTER-WIDE: `ls /etc/pve/nodes/*/qemu-server/105.conf /etc/pve/nodes/*/lxc/105.conf` on any host finds nothing. (`qm config <id>` on one node is NOT a freedom check -- it only reads that node's folder; see Pitfalls.)
   - `pvesm status` -- local-lvm has room (a 32 GB disk is noise).
   - Template on THIS node: `qm config <template_id>` shows the
     Ubuntu 24.04 cloud template, `template: 1`.
   - Storage content: the `local` datastore needs `snippets` +
     `images` for the cloud-init snippet upload and config drive
     (proven in this fleet by the k3s builds on the same node, but
     re-check after any storage change).
2. **tfvars.** Copy `terraform/terraform.tfvars.example` to
   `terraform.tfvars` (gitignored) and fill in the real endpoint,
   the real `.27/24` address, gateway, and your SSH public key --
   copying values from the k3s module's tfvars on the same machine
   beats retyping them. Then the gate: no doc-range survivor --
   `Select-String -Path .\terraform.tfvars -Pattern '192\.0\.2\.'`
   returns nothing. (A from-scratch plan never dials the API, so a
   placeholder endpoint passes plan and fails apply -- the pbs
   module's first-apply lesson, gated here.)
3. **Env legs, same PowerShell window.** `PROXMOX_VE_API_TOKEN` plus
   the SSH leg (`PROXMOX_VE_SSH_USERNAME` / `_PASSWORD` -- the
   snippet upload rides SSH; plan never exercises it). Secrets via
   the `Read-Host -AsSecureString` pattern, verified by name/shape
   only. Env vars die with the window.
4. **Init + plan.** Expect **2 to add, 0 to change, 0 to destroy**
   (the user-data snippet file + the VM). Plan is the gate: audit
   node, VMID, template ID, IP, CPU type before anyone applies.
5. **Apply + first boot.** Cloud-init runs package updates and
   installs Docker + Tailscale, so first boot takes a few minutes.
   Proof: SSH in as the cloud-init user on the `.27`, and
   `qm agent 105 ping` answers from the host side.
6. **Tailscale enroll (by hand).** `sudo tailscale up` (plain -- NO
   `--ssh`), then verify `tailscale debug prefs` shows RunSSH
   false and lock it: `sudo tailscale set --ssh=false`. Standing
   lab rule: Tailscale SSH stays OFF.
7. **Patch before it serves.** Run the fleet update workflow
   (`updates/` in this repo) check -> apply -> reboot if the
   kernel moved. A DNS server goes live current, not stale.
8. **Port 53 landmine (Ubuntu VM -- the step everyone skips).**
   Ubuntu's `systemd-resolved` stub listener squats on
   127.0.0.53:53, which collides with Docker publishing port 53.
   Check first: `ss -tulpn | grep :53`.
   Fix: set `DNSStubListener=no` in `/etc/systemd/resolved.conf`,
   restart `systemd-resolved`, and repoint `/etc/resolv.conf` at
   `/run/systemd/resolve/resolv.conf` (the upstream list -- the
   stub symlink would point the host at a listener that no longer
   exists). Verify: the host still resolves (`getent hosts
   example.com`) and nothing owns :53 except what you start next.
   The VM's own upstream is a public resolver by design (see
   `dns_servers` in the module) -- it never resolves through
   itself.
9. **Deploy Pi-hole.** Clone this repo on the VM, copy
   `pihole/docker-compose.yml` to `~/pihole/`, `docker compose up
   -d`. First start prints a random admin password ONCE in
   `docker compose logs pihole` -- ignore it and set your own:
   `docker exec pihole pihole setpassword`, stored in the password
   manager at that moment. Admin UI: `http://<vm-ip>/admin`,
   LAN-only, no port forwards, ever.
10. **Acceptance (Stage 1 proof).**
    - `dig @<vm-ip> one.one.one.one` -- real answer.
    - `dig @<vm-ip> doubleclick.net` -- 0.0.0.0 (gravity is
      working, not just the resolver).
    - Admin UI loads, query log shows both test queries.
    - One real device pointed at it by hand for a day before
      Stage 2 is even discussed.
    - Add the VM to the backup jobs once the PBS datastore
      cutover settles (the cloned disk carries `backup=1`); the
      compose state in `~/pihole/etc-pihole` rides inside it.

## Pitfalls already paid for (fleet lessons, applied here)

- `versions.tf` ships with the module from birth (the pbs module's
  init failure was its absence).
- VMID freedom checks are cluster-wide or worthless: first-choice
  103 read "does not exist" from the build node while a PBS-restored
  VM already held 103 on another node (single-node `qm config` only
  reads the local folder). The clone died at the config rename
  ("File exists") until the build moved to 105 and the check became
  the `/etc/pve/nodes/*/` glob in step 1.
- Plan does not prove the endpoint or the SSH leg -- tfvars gate
  (step 2) + same-window env ritual (step 3) exist because of
  that.
- Commit `.terraform.lock.hcl` with the module's first push from
  the workstation clone (the k3s batch's leftover).
- Whitespace-sensitive files travel via git pull, never paste.
