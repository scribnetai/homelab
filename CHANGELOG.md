# Changelog

## 2026-09-27 — Terraform provisioning for the k3s nodes
- New `k8s/terraform/`: `bpg/proxmox` Terraform that builds the two k3s Proxmox
  VMs (server on NUC-1, agent on NUC-2) as full clones of one Ubuntu 24.04
  cloud-init template — 2 vCPU / 4 GB / 32 GB each (matches the k8s README
  topology), lab-net IPs, Tailscale + qemu-guest-agent via cloud-init snippets.
- `k8s/terraform/build-template.sh`: one-time golden-template build, run on a
  Proxmox node.
- `k8s/README.md`: new "Provisioning the VMs" section; bring-up step 1 now
  points at Terraform instead of manual VM creation.
- Notes: Proxmox API token via `PROXMOX_VE_API_TOKEN` env var (never committed);
  `tailscale up` stays a manual one-per-VM step — no Tailscale auth keys in the
  repo. Snapshot both VMs before running k3s-install.sh (rewind point for
  learning).

## 2026-09-27 — Kubernetes track: k3s scaffold
- New `k8s/` tree, coupled with the VPS setup in this same repo (one repo, two
  runtimes). Same container images either way; the orchestrator is what differs.
- `k8s/k3s-install.sh`: server/agent bootstrap for Proxmox VMs (control plane
  on NUC-1, worker on NUC-2). Nodes join over Tailscale IPs so the VPS can
  later join as a hybrid agent with the same commands.
- `k8s/manifests/demo-whoami.yaml`: first smoke-test workload (Namespace +
  Deployment + Service), including the "delete a pod and watch it reschedule"
  exercise.
- `k8s/README.md`: topology, bring-up steps, and an ordered learning path
  (whoami → Ingress → Longhorn → Helm → ArgoCD → migrate a Compose service).
- `k8s/LEARNING.md`: containers-vs-VMs and every core K8s object mapped to
  datacenter/VMware mental models.
- Deliberate: Kuma stays on the VPS via Compose — the watcher lives outside
  the cluster's failure domain.

## 2026-09-27 — Uptime Kuma v1 → v2
- `vps/docker-compose.yml`: image moved from `louislam/uptime-kuma:1` to `:2`.
  v1 is end-of-life (no security fixes); v2 is the maintained line. The (still empty)
  v1 SQLite database auto-migrates on first v2 start.

## 2026-09-27 — Corrected VPS type/price
- Hetzner no longer offers the old CX22 (~€3.79/mo) in Ashburn; the entry shared tier
  there is now CPX12 (1 vCPU, 2 GB RAM, 40 GB SSD) at $13.49/mo — still inside the
  $10–20/mo budget. 1 vCPU / 2 GB is plenty for Kuma + Tailscale (+ Beszel later).
  README quickstart updated.

## 2026-09-27 — Security fix: Kuma no longer published publicly
- `vps/docker-compose.yml`: Kuma binds to `127.0.0.1:3001` only. Docker programs
  iptables directly and bypasses ufw, so the previously published port was reachable
  from the public internet despite the firewall.
- Kuma is exposed on the tailnet via `tailscale serve` (automatic HTTPS on the
  MagicDNS name) instead.
- `README.md`: `tailscale serve` step added to the quickstart, plus Security notes
  (Hetzner firewall as defense in depth).

## 2026-09-27 — Initial commit
- `vps/cloud-init.yaml`: portable first-boot bootstrap (Ubuntu 24.04, Docker from the
  official apt repo, Tailscale, ufw default-deny with SSH + tailnet allowed,
  unattended-upgrades)
- `vps/docker-compose.yml`: Uptime Kuma pinned to `louislam/uptime-kuma:1`, state in
  the named volume `kuma-data`
- `vps/backup.sh` / `vps/restore.sh`: tarball backup/restore for the Kuma data volume
- `README.md`: Hetzner CX22 (Ashburn) quickstart, backup/restore, provider-move procedure
