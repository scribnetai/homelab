# Changelog

## 2026-10-25 — Repository history rewritten (owner-directed purge)
- The full history was rebuilt without the lab-specific working files and identifiers removed above: the Factorio working set and the one-shot snapshot manifest never exist in this history, and historical blobs that quoted the planned lab segment or generated resource IDs now carry documentation-range / placeholder values. All 75 commits, messages, authors, and dates are preserved; commit SHAs changed. EXISTING CLONES MUST RESYNC before pushing (git fetch + git reset --hard origin/main, or re-clone) — a push from a stale clone would resurrect the old history. Note: GitHub may retain unreachable objects server-side for a time after a rewrite; a support request is the way to force their expiry.

## 2026-10-25 — Factorio working files removed from the public repo
- The Factorio guide, test-run sheet, friends-access sheet, helper scripts, and manifest that landed here during the Oct 25 test session were working documents carrying lab-specific detail (VM identifiers and sizing, node and host placement, a node label bearing the owner's domain, the external-access design). Removed at the owner's direction — public repos get sanitized artifacts only; session runbooks with lab specifics live in private files. Verified after removal: every path returns 404 and the tree is back to the pre-Factorio file count. No IP addresses, tailnet names, usernames, or credentials were in the removed files (checked before deletion). Git history still contains them; whether to rewrite history is the owner's open call.

## 2026-10-25 — Factorio dedicated server kit (test-validated)

- Added the Factorio server kit under `k8s/`: guide (`FACTORIO.md`),
  manifest (`manifests/factorio.yaml` — StatefulSet pinned to the
  agent node, Longhorn `longhorn-rep2` PVC, game port as hostPort,
  RCON never exposed), and the deploy kit in `k8s/factorio/`
  (save-upload and server-configure scripts in PowerShell + bash,
  stage-2 Tailscale friends-access runbook, and `TEST-RUN.md`).
- Validated end to end on a disposable test instance the same day
  (gates T0–T8: deploy, crafted-save upload, password/admin
  configure, join, pod-kill resilience, clean teardown), then torn
  down completely. The live deploy is a separate, later pass.
- Public copy sanitized per the repo standard: real LAN/tailnet
  addresses, the tailnet name, generated volume IDs, and personal
  usernames replaced with placeholders; the full operational copy
  lives in the private dedicated-servers repo. The kit's
  PowerShell lessons (ASCII-only scripts, native-argument quoting
  traps, `kubectl cp` colon parsing) are written up in the guide's
  operations notes.


## 2026-10-24 — Changelog scrub: planned-segment CIDR removed
- At his direction, the planned lab segment's CIDR quoted in the Sep 28 sanitize entry (and repeated in the review entry below) is removed from this file; both entries now describe the change without printing the range. Verified by a repo-wide rescan: no private-range lab addresses remain anywhere at HEAD.

## 2026-10-24 — Repo-wide sanitization review + README refresh
- Full review at his request: all 35 files at HEAD scanned for the real tailnet name, tailnet/LAN/public IPs, emails, token/key shapes, key fingerprints, MACs, hardware serials, his username, and generated k8s IDs (PVC/snapshot names). Result: CLEAN — every match was a placeholder (`<tailnet>`, `<redacted>`), a generic range, or cloud-init's standard NOPASSWD user config. The only judgment call left in place: a Sep 28 changelog entry quoting the planned lab-net design range (removed at his direction — see the scrub entry at the top of this file). Git HISTORY still contains tonight's earlier files (incl. the deleted snapshot manifest); a history rewrite stays his call.
- README rewritten to match reality: the VPS has been on AWS since Oct 17 (the Hetzner quickstart was two providers stale); layout now covers hermes/, k8s/terraform, Longhorn + the rep2 StorageClass warning, PocketBase + the operator Ingress, and Headlamp; new Access model section (tailnet-only, SSM break-glass, port-forward conventions); security notes now carry the two Oct 24 lessons — bare Snapshot CRs are mirrors that get GC'd, and Tailscale Ingress hostnames come from spec.tls hosts, not the annotation.

## 2026-10-24 — Correction: the snapshot manifest removal actually landed now
- The earlier "manifest removed" commit's tree patch only walked the repo's top level and silently missed the nested file; `k8s/longhorn/snapshots/<pre-schema-snapshot>.yaml` stayed live until this pass. It is now deleted via the Contents API and verified gone (GET returns 404). The manifest also carried the volume's generated PVC name — an opaque internal ID, not a credential and no route to the cluster exists publicly — but it never belonged in a public repo under this project's sanitization standard. The gate entry below no longer prints the raw snapshot ID either; the designation lives in the private Lab Ledger.

## 2026-10-24 — Exposure gate for tailnet doors (k8s/EXPOSURE.md)
- New `k8s/EXPOSURE.md`: the gate every cluster UI passes before it gets a Tailscale-operator Ingress — gate checklist (own auth or an approved compensating control, least-privilege default identity, ClusterIP only, no Funnel ever, secrets in Secrets/vault only, verification pack recorded) plus the exposure matrix. Current state recorded: PocketBase APPROVED + LIVE (verified on-tailnet, public DNS returns no address records); Headlamp STAGED (Ingress manifest written, NOT applied — port-forward only until the gate's first live decision); Longhorn UI DENIED/parked (no login of its own); Grafana ELIGIBLE but not yet approved ahead of Phase 2; Prometheus and Alertmanager PERMANENTLY DENIED (no built-in auth — ClusterIP only, forever). Failed check = door comes down first, diagnosis second. `k8s/README.md` links the gate. Documentation/policy only — this commit changes no live Ingress, ACL, or Service.

## 2026-10-24 — Step 7 snapshot gate executed via the UI
- The pre-schema restore point exists: a Longhorn snapshot of the PocketBase volume (created 2026-10-24T23:59:52Z via the Longhorn UI's manager path; ~247 MB captured; auto-named — the current UI offers no name field; its full name is recorded in the Lab Ledger's Key Commands tab, which designates it as THE pre-schema restore point). readyToUse was still finalizing at last read — confirm it reads true before relying on a restore.

## 2026-10-24 — Snapshot gate method corrected: bare Snapshot CRs are mirrors, not requests
- The pre-schema gate manifest added earlier today (`k8s/longhorn/snapshots/<pre-schema-snapshot>.yaml`) does not work on Longhorn v1.13 and is REMOVED. Live evidence from longhorn-manager logs: the CR was admitted (webhook set finalizer/dataEngine/labels/owner), declared "snapshot was removed from engine" 15 ms later, and deleted by the engine controller's syncSnapshotCRs — a directly-created Snapshot CR is treated as an orphan mirror of engine state and garbage-collected; it never requests an engine snapshot. The volume itself is innocent (all status conditions in their good states, TooManySnapshots False). Snapshots are created engine-first via the manager (UI or API); the gate is executed from the Longhorn UI instead, and the resulting manager-created CR is the verification.

## 2026-10-24 — Step 7 snapshot gate manifest
- `k8s/longhorn/snapshots/<pre-schema-snapshot>.yaml`: a one-shot Longhorn Snapshot CR for the PocketBase volume, the pre-schema restore point required by the build's Step 7 gate. Committed as the dated record of the gate; the snapshot itself is verified live (status.readyToUse) before any collection is created.

## 2026-10-24 — PocketBase Ingress hostname: TLS-hosts lever (annotation attempt corrected)
- The `tailscale.com/hostname` annotation does not set an Ingress's device name — verified in the operator source (cmd/k8s-operator `hostnameForIngress`): an Ingress takes its name from the first label of `spec.tls[0].hosts[0]`, falling back to `<namespace>-<name>-ingress`; the annotation is the Service/LoadBalancer mechanism. Two live applies (including a cold-start recreate with a fresh proxy identity) confirmed the generated name both times. The manifest now sets `spec.tls` hosts `["pocketbase"]`, drops the annotation, and its header comment records the real mechanism.

## 2026-10-24 — PocketBase tailnet hostname pinned (Step 6 live finding)
- The Tailscale operator is installed (ACL tagOwners + OAuth client, Devices Core RW + Auth Keys Write, tagged tag:k8s-operator; helm release deployed). First Ingress apply provisioned end-to-end — proxy pod Running, device created — but at the operator-generated name `finance-pocketbase-ingress.<tailnet>.ts.net`: with no hostname set, the operator derives the name from namespace+ingress name, not the resource name alone as the manifest comment assumed. `k8s/manifests/pocketbase-ingress.yaml` now pins `tailscale.com/hostname: "pocketbase"` and its comment records the real behavior.

## 2026-10-24 — updates/README: script distribution documented
- New "Getting the script onto a host" section: the exact fetch + sha256 fingerprint check + run block used in the phase-2 rollout, with the fingerprint compared against the trusted homelab-vps clone (the pin is deliberately not printed — it rotates with every script change). Step 2's invocation now matches the /tmp flow. Phase-2 state: k3s-agent patched clean (8 userland, verified Ready); k3s-server check ran as expected.

## 2026-10-24 — check-updates.sh: phased updates reported (Beszel count reconciled)
- The test-bed VPS caught a real discrepancy: after a fully successful apply + reboot, Beszel still showed 2 updates (software-properties 0.120 -> 0.120.1) while the checker read 0. Root cause in apt's own words: "The following upgrades have been deferred due to phasing" — this apt defers phased SRUs in bulk upgrade simulations, while Beszel's list-based count includes them. Neither tool was wrong; they were counting different sets.
- `updates/check-updates.sh` now parses the phasing section and reports it as its own line (names included) in check output and in the post-apply re-check, so checker and badge reconcile by construction (badge total = installable + phased). Phased updates are deliberately NOT forced — they are Ubuntu's rollout canary; the named-install override is documented in `updates/README.md`, which now explains the mechanism in the workflow. `vps/README.md`'s badge note points at it. (Same pass: the --apply "nothing to apply" path now still restarts the agent, as the every-run badge refresh intended.)

## 2026-10-24 — check-updates.sh: Beszel badge refresh on every run
- The agent restart that forces the hub's updates badge to re-check (previously apply-mode only) now ends EVERY run of `updates/check-updates.sh` — a plain read-only check also leaves the board truthful. Motivated by the first test-bed run: the checker surfaced a pre-existing reboot-required state (kernel + libc6, from unattended security updates) that the cached badge had never shown.

## 2026-10-24 — updates/: fleet update workflow (test bed = the VPS)
- New `updates/README.md`: the check-then-apply workflow the Beszel dashboard invited — the hub's Updates column is the (cached) fleet picture, the host's simulated dist-upgrade is the truth, and application is a per-host human decision with blast-radius ordering rules (never both Proxmox hosts back-to-back: the k3s control plane lives on one and Longhorn's replica pair spans the two; VPS anytime; workload VMs when quiet; kernel updates carry their reboot in the same window).
- New `updates/check-updates.sh`: one self-contained script per apt host. Default mode is read-only (metadata refresh + simulated count/list + reboot-required state); `--apply` runs the upgrade interactively (no -y by design in this phase), re-checks, and restarts beszel-agent so the hub badge returns to truthful immediately. Handles root-without-sudo (Proxmox) and sudo users.
- Scope: test bed is the cloud VPS (24 pending at first check); fleet rollout is phase 2. Containers stay on their own flow (pull + recreate + changelog); nothing anywhere auto-applies.

## 2026-10-24 — vps/README.md: monitoring-plane ops notes
- New `vps/README.md` documenting how the cloud services behave in operation: localhost binds + the two tailscale serve doors, agent enrollment by Tailscale IP (pairing is by token, not address), the Docker-socket caveat for container stats on containerd hosts, backups pointer, and why the Kuma -> Beszel monitor uses the compose network instead of the serve URL.
- Headline note, learned live the same day: Beszel's "updates available" count is cached — metrics refresh ~1/min, but the update check runs on a slow cycle and at agent start. After patching a host, force the re-check with `systemctl restart beszel-agent` (as root; the Proxmox hosts have no sudo) and verify against the host's own simulation: `apt-get -s dist-upgrade | grep -c "^Inst"` (0 = fully patched).

## 2026-10-24 — VPS backups brought under the GFS standard (nightly cron + rotation)
- `vps/backup-rotate.sh` (new): ported from the Enshrouded kit's rotate script — the fleet backup standard — and adapted to backup.sh's stamp-paired tarballs (a set = the kuma-data + beszel-data tarballs from one run). Sunday's set -> weekly (keep 5), the 1st's -> monthly (keep 12), Jan 1st's -> yearly (keep 3); tiers live in `backups/archive/` with their own rotate.log. One deliberate delta vs the original: the game image self-trims its dailies, backup.sh does not, so this script also prunes the root to the newest 14 sets. Fixture-tested locally before shipping (trim, all three promotions, tier pruning, empty-dir no-op).
- Nightly schedule documented in the README (backup 04:15 ET, rotate 04:45 ET, CRON_TZ pinned, interpreter-explicit paths) for install via crontab on the server — the VPS had NO backup cron before today; backup.sh was manual-only.
- Honest gap, recorded rather than smoothed over: all tiers are ON-box. The off-box copy target is a pending decision (same gap exists on the Enshrouded server, whose GFS tiers also live on its own VM).

## 2026-10-24 — Beszel build close-out (agents, watcher, backups)
- Agents live on proxmox, proxmox2, the Enshrouded VM, and the VPS itself — all enrolled by Tailscale IP. (The first Proxmox enrollments used LAN-IP labels and reported anyway via the agents' outbound channel; they were deleted and re-enrolled the same day. Verified from the VPS that no subnet route exists: nothing in the tailnet map, LAN egress leaves via the cloud gateway, and the agent port is unreachable at LAN addresses.)
- Kuma now monitors the hub itself at http://beszel:8090 over the shared compose network. The serve URL cannot be monitored from inside a container on the same host: containers cannot resolve tailnet names (host-resolver bypass; the MagicDNS service address does not answer bridge-sourced queries), and connections to the host's own tailnet serve ports blackhole. A tailscaled failure stays cross-covered — every tailnet monitor flips together.
- `vps/backup.sh` now also tarballs `beszel-data` (decision: keep the metrics history), and `vps/restore.sh` picks the volume + service from the tarball name (`kuma-data-*` / `beszel-data-*`). The hub image stays on the floating `:latest` tag (decision, 2026-10-24).
- Cost check (Step 0 before/after pair): hub container 12.67MiB / 0.00% CPU at idle; host available RAM 1.0Gi -> 990Mi after hub + agents. README updated (Beszel live; the What's-next item is retired).

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
  `terraform.tfvars.example`), and the real lab IP schema (replaced with the
  documentation range `192.0.2.0/24` in `variables.tf`,
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
