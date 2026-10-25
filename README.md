# Homelab

Infrastructure-as-code for a home lab: a two-node Proxmox cluster, a k3s
Kubernetes cluster on top of it, an off-site monitoring VPS in AWS, and an
AI-agent host — every service defined as code, nothing hand-configured.
Remote access is Tailscale-only throughout: no public listeners, no inbound
port forwards, no published internal hostnames.

Companion doc: the **Homelab Runbook** (living document — inventory, topology,
addressing plan, bring-up checklists). Code lives here; narrative lives there.

## Layout

- `vps/` — the off-site NOC on an AWS EC2 instance (security group: **zero
  inbound rules**; reached over the tailnet or via SSM Session Manager).
  - `docker-compose.yml` — Uptime Kuma (up/down monitoring) and the Beszel
    hub (per-host metrics). Both bind to localhost only and are exposed on
    the tailnet via `tailscale serve` (see Security notes).
  - `backup.sh` / `restore.sh` / `backup-rotate.sh` — nightly tarball backups
    of both data volumes, with GFS retention tiers (see Backup & restore).
  - `README.md` — ops notes: exposure model, Beszel agent enrollment and
    pairing, the updates-badge refresh quirk, and why Kuma monitors the hub
    over the compose network instead of its tailnet URL.
- `k8s/` — the Kubernetes track: k3s (one control-plane VM, one worker VM)
    on the two Proxmox hosts. See `k8s/README.md`.
  - `terraform/` — the bpg/proxmox config for the node VMs (provider needs
    BOTH auth legs: an API token and an SSH credential for snippet uploads).
  - `longhorn/` — Longhorn replicated storage (2 replicas across the two
    nodes) and the custom `longhorn-rep2` StorageClass. The bundled class
    hardcodes 3 replicas — never use it on a 2-node cluster.
  - `manifests/` — apps on the cluster. Today: PocketBase (finance
    namespace, single-replica StatefulSet on Longhorn), fronted by a
    Tailscale-operator Ingress so it gets a tailnet-only HTTPS name.
  - `headlamp/` — Headlamp, the cluster web UI: ClusterIP-only, hardened
    values (no default cluster-admin binding, Helm integration off),
    short-lived viewer tokens, no standing admin identity.
- `hermes/` — the Hermes Agent host (a VM on Proxmox): multi-persona local
  AI, deployed as a container; secrets only in the deployment's `.env`.
- `updates/` — the fleet update workflow: Beszel detects, the host verifies,
  a human applies interactively. Nothing auto-applies anywhere. The checker
  reports Ubuntu phased updates separately from installable ones.
- `CHANGELOG.md` — what changed, when. Every change lands with an entry.

## Access model

- **Everything is tailnet-only.** Services bind localhost or a tailnet
  interface; `tailscale serve` and the Tailscale Kubernetes operator
  provide the HTTPS doors. Tailnet *names* for lab services are not
  published in public DNS, and public exposure is a rejected design.
- **Break-glass:** SSM Session Manager reaches the VPS with no network path
  at all (IAM-authenticated, MFA on) — the door that works when Tailscale
  itself is down.
- **Kubernetes from the workstation:** `kubectl` talks to the cluster API
  over the tailnet. Port-forward conventions on the workstation:
  8080 = Longhorn UI, 8081 = Headlamp, 8090 = PocketBase (legacy; it has a
  tailnet Ingress now). Longhorn's UI has no auth of its own — it is only
  ever reached by port-forward, never exposed.

## Security notes

- **Docker bypasses the host firewall.** Docker programs iptables directly,
  so a published port would be public despite ufw's default-deny. That is
  why every container here binds `127.0.0.1` and reaches users only through
  `tailscale serve`.
- **Secrets never live in this repo.** Credentials sit in the operator's
  password manager or a gitignored `.env` on the target host; manifests and
  configs carry placeholders only. Real IPs, tailnet names, and generated
  resource IDs are kept out of committed files for the same reason.
- **Longhorn snapshots are created engine-first** (UI or manager API).
  A Snapshot CR created directly with kubectl is only a mirror of engine
  state and gets garbage-collected — it never requests a snapshot.
- **Tailscale Ingress hostnames** come from `spec.tls[0].hosts[0]`, not
  from the `tailscale.com/hostname` annotation (that one is for
  LoadBalancer Services).

## Backup & restore

- VPS: `./backup.sh` in `vps/` tarballs both data volumes (Kuma + Beszel)
  into `backups/`. A nightly cron runs it, and `backup-rotate.sh` applies
  the fleet GFS standard to the tarball sets: newest 14 sets in `backups/`,
  plus promoted tiers in `backups/archive/` (weekly = Sunday's set, keep 5;
  monthly = the 1st's set, keep 12; yearly = Jan 1st's set, keep 3).
  Crontab lines invoke the interpreter explicitly (`/usr/bin/bash ...`) —
  files that travel via zip/Windows lose their exec bit.
- Known gap: every tier currently lives ON the box it protects. An off-box
  copy target is a parked decision — until then, copy the tarballs from
  `backups/` somewhere safe by hand.
- Restore (fresh server, same repo): `docker compose up -d` once, then
  `./restore.sh backups/<file>.tgz` (the tarball name selects the volume).
- Game servers follow the same GFS standard (see the dedicated-servers
  repo); Longhorn volumes carry their own snapshot/restore story per app.

## Moving providers

The VPS is disposable by design. `cloud-init.yaml` builds the box on any
cloud that takes user data; `docker-compose.yml` plus the data volumes
*is* the app.

1. `./backup.sh` on the old box, copy the tarballs off.
2. New VM anywhere, same `cloud-init.yaml` pasted as user data (ASCII
   only — one mangled character makes cloud-init reject the whole file).
3. Clone this repo, `./restore.sh backups/<file>.tgz`, `docker compose up -d`.
4. `tailscale up` with the **same node name** — MagicDNS stays stable —
   then re-apply the `tailscale serve` config.
5. Update DNS if anything public pointed at the old IP. Done.

## What's next

- A NOC page that brings the monitoring doors and the lab's key-commands
  list together in one place (the list currently lives in the lab ledger).
- Off-box backup copies (above).
- Monitoring Phase 2: kube-prometheus-stack on the k3s cluster (Grafana
  gets the only Ingress).
