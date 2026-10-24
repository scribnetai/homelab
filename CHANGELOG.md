# Changelog

## 2026-10-24 — Beszel metrics hub on the cloud VPS (compose service #2)
- `vps/docker-compose.yml`: added the `beszel` service (henrygd/beszel) next to Uptime Kuma — localhost-only bind `127.0.0.1:8090` (Docker bypasses ufw; the UI reaches the tailnet via a second `tailscale serve` HTTPS port, 8443), named volume `beszel-data` so backup/restore find it regardless of project directory. Kuma's service definition is unchanged.
- Step 0 resource baseline captured pre-deploy (Kuma alone on the t4g.small: 802Mi used / 1.0Gi available of 1.8Gi RAM, no swap; disk 13G free; uptime-kuma 150.8MiB) — the before/after pair feeds the 2026-10-25 alerting-review resource gate (whether a third small container fits beside Kuma + Beszel).
- Fix (same day, first `up` failed): volume target corrected `/beszel/data` → `/beszel_data`. The staged file predated the current image layout — v0.21.1 is a scratch image whose only payload is the binary at `/beszel` (a file), so the old path cannot exist; verified via `docker export` of the pulled image and against the official docs. Failure-driven capture per house rule: fix + comment in the compose file + this entry in one pass.

## 2026-10-24 - Headlamp in-cluster web UI (Phase 1, hardened)
- New `k8s/headlamp/`: Headlamp chart/app 0.46.0 in namespace `headlamp` - the maintained, web-native successor to the archived Kubernetes Dashboard (OpenLens desktop builds are unmaintained since 2023 and were passed over). `values.yaml` reproduces the live install with the upstream defaults deliberately reversed: the chart's default ServiceAccount-to-`cluster-admin` binding is disabled, `unsafeUseServiceAccountToken` and `enableHelm` are pinned off (the latter is CVE-2025-14269 territory), Service is ClusterIP only.
- `rbac.yaml`: login identity model - daily `headlamp-viewer` (built-in `view` + a small nodes/metrics role so the overview gauges render), read-only with no Secrets, no exec, no writes; tokens minted via TokenRequest at 24h, stored nowhere. No standing admin identity; admin is minted ad hoc at 1h.
- `ingress.yaml`: Phase 1B tailnet door - Tailscale operator Ingress (host derived from the resource name, same pattern as `k8s/manifests/pocketbase-ingress.yaml`), pending the operator install. Tailnet-only by construction; Tailscale Funnel is never used and the tailnet policy is verified to grant no funnel attribute.
- Verified live on deploy day: pod Running, Service ClusterIP-only, and the overview rendering both nodes Ready with live CPU/memory under the viewer identity - which also proves the metrics role works. The `auth can-i` pack in the folder README is the standing check for the no-secrets / no-delete / no-exec boundaries.

## 2026-10-21 — Hermes Agent deployment as IaC (two-service compose)
- New `hermes/`: the deployed `docker-compose.yml` for the Hermes Agent VM — one file, two services sharing one data volume: `hermes` (messaging gateway + cron) and `hermes-backend` (`hermes serve`, the Hermes Desktop / dashboard backend, published only on the VM's Tailscale IP — placeholdered in the committed file). Auth, secrets, and operating rules in `hermes/README.md`; the data dir is host-local and gitignored, secrets only in its `.env`.

## 2026-10-19 — k3s Terraform: first live apply lessons (per-node templates, SSH leg, storage prereqs)
- Per-node templates — corrects the 2026-09-28 notes below: with local
  storage the bpg/proxmox provider runs the clone on the target node, so
  every node hosting k3s VMs needs its own template copy, and in a
  cluster the copies take distinct VMIDs (9000 / 9001 via
  `TEMPLATE_ID=9001`). `main.tf` now sets `template_id` per node in
  `locals.nodes`; the global `template_id` variable was removed from
  `variables.tf` / `terraform.tfvars.example`. (Driven by the first live
  deployment session: k3s-server applied cleanly once these were fixed.)
- The provider's second auth leg is documented: cloud-init snippet
  uploads go over SSH, not the API — `PROXMOX_VE_SSH_USERNAME` /
  `PROXMOX_VE_SSH_PASSWORD` (or ssh-agent keys) alongside
  `PROXMOX_VE_API_TOKEN`. Env vars only, never files.
- Storage prerequisite documented: the cloud-init datastore (`local`)
  must allow the **Snippets** and **Disk images** content types, or the
  snippet upload and cloud-init ISO generation fail during apply.
- `.gitignore`: added Terraform local files (`*.tfvars`, `*.tfstate*`,
  `.terraform/`, `*.tfplan`) — previously covered by convention only.

## 2026-09-28 — Sanitize: remove remaining personal SSH username
- Replaced the last personal SSH username references (`techops` → `labuser`)
  missed by the earlier sanitize pass: `README.md` quick-start step,
  `vps/cloud-init.yaml` (user creation, docker group, final message), and
  `vps/backup.sh` (scp example). Matches the `labuser` convention used in
  `k8s/terraform/variables.tf`.

## 2026-09-28 — Sanitize repo: remove personal identifiers
- Combed the whole repo for personal references. Removed the GitHub org/user
  name (`vps/cloud-init.yaml`, `README.md` clone URLs now use
  `github.com/<your-org>/homelab`), the personal SSH username default
  (`scribnet` → `labuser` in `k8s/terraform/variables.tf` and
  `terraform.tfvars.example`), and the real lab IP schema (`192.0.2.0/24`
  → documentation range `192.0.2.0/24` in `variables.tf`,
  `terraform.tfvars.example`, `k8s/README.md`). Fill in your own values in
  `terraform.tfvars` (gitignored, never committed).
- `k8s/README.md`: also corrected two leftover lines that still said
  `build-template.sh` runs "on each node" — it's once per cluster (per node
  only if standalone), matching `k8s/terraform/README.md`.

## 2026-09-28 — k3s Terraform review fixes
- `k8s/terraform/versions.tf`: `bpg/proxmox` pin tightened `>= 0.60` → `~> 0.111`
  (0.111.x verified current 2026-08) — a future 0.x breaking change can't
  surprise a later `terraform init`.
- Template docs corrected: the clone is node-local, so `build-template.sh`
  must run on EACH standalone Proxmox node (same VMID 9000 on both); clustered
  nodes need it only once. Updated `k8s/terraform/README.md`,
  `build-template.sh` header, and the `k8s/README.md` provisioning section.

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
