# Kubernetes track (k3s)

The container-learning side of the homelab, kept in the same repo as the VPS
setup on purpose: **one repo, two runtimes**. The VPS runs standalone Docker
Compose (Uptime Kuma lives there deliberately — the watcher stays outside the
cluster's failure domain). The lab runs k3s. Same container images either way;
different orchestration.

## Topology

- **k3s server (control plane):** Proxmox VM on NUC-1 — 2 vCPU / 4 GB RAM /
  32 GB disk, on the lab net (`192.0.2.0/24`).
- **k3s agent (worker):** Proxmox VM on NUC-2, same sizing.
- **Access:** `kubectl` from your PC over Tailscale. The install script adds the
  node's Tailscale IP as a TLS SAN, so the kubeconfig just works remotely.
- **VPS:** stays Compose. Phase 2 (optional, later): join the VPS as a k3s
  agent over Tailscale for a hybrid home+cloud cluster. Not day one — learn on
  hardware you can power-cycle first.

## Provisioning the VMs (Terraform)

The two Proxmox VMs are defined as code in [`terraform/`](terraform/) (the
`bpg/proxmox` provider): full clones of an Ubuntu 24.04 cloud-init template
(VM 9000 — build once per cluster with `build-template.sh`, or on each node if
standalone), with cloud-init
installing the qemu guest agent + Tailscale and assigning the lab-net IPs
(`192.0.2.21/24` server, `.22/24` agent).

Flow: `build-template.sh` (once per cluster, or per node if standalone) → fill in `terraform.tfvars` →
`terraform apply` → `tailscale up` on each VM → **snapshot both VMs** (your
rewind point for when the cluster inevitably breaks during learning) → continue
with bring-up step 2 below. Full instructions in [`terraform/README.md`](terraform/README.md).

Auth is via the `PROXMOX_VE_API_TOKEN` env var (Datacenter → Permissions → API
Tokens) — never committed. `tailscale up` stays a manual one-per-VM step for
the same reason: no auth keys in the repo.

## Bring-up

1. During the lab bring-up (after Proxmox is up), provision the two VMs with
   Terraform — see [Provisioning the VMs](#provisioning-the-vms-terraform) below.
   Then `tailscale up` on each VM.
2. On the server VM: `sudo bash k3s-install.sh server` — it prints the agent join
   token at the end.
3. On the agent VM:
   `sudo K3S_URL=https://<server-tailscale-ip>:6443 K3S_TOKEN=<token> bash k3s-install.sh agent`
4. On your PC: copy `/etc/rancher/k3s/k3s.yaml` from the server, replace
   `127.0.0.1` with the server's Tailscale IP, save as `~/.kube/homelab.yaml`,
   set `KUBECONFIG` to it.
5. `kubectl get nodes` → both nodes `Ready`. Then:
   `kubectl apply -f manifests/demo-whoami.yaml`

## Learning path (in order — each step teaches one real concept)

1. **Smoke test + break it.** Deploy whoami, `kubectl get pods -n demo`, then
   `kubectl delete pod -n demo <name>` and watch the Deployment recreate it.
   That's the HA lesson in 30 seconds — no vMotion, just rescheduling.
2. **Ingress.** k3s ships Traefik. Write an `Ingress` for whoami on a lab
   hostname and hit it through the node IP. This is the L7 load-balancer
   concept.
3. **Storage.** Default `local-path` provisioner first (one node, one disk),
   then install **Longhorn** for replicated volumes. This is where Kubernetes
   stops feeling like magic and starts feeling like a real distributed system.
4. **Helm.** Install something real via chart instead of raw YAML —
   `kube-prometheus-stack` is the classic (and pairs with the Kuma story:
   metrics vs uptime).
5. **GitOps.** **ArgoCD** pointed at this repo's `k8s/manifests/`. Cluster
   state becomes a pull request. This is the endgame of the "everything as
   code" idea the VPS setup started.
6. **Migrate a Compose service.** Pick one (AdGuard Home is a good first) and
   move it from Compose into the cluster. You'll feel exactly what K8s adds —
   and what it costs in complexity.

Concepts behind all of this: [`LEARNING.md`](LEARNING.md) — containers vs VMs,
and every K8s object mapped to something you already know from the datacenter
world.

## Notes

- `K3S_VERSION` env var pins the k3s version (e.g.
  sudo K3S_VERSION=v1.34.2+k3s1 bash k3s-install.sh server). Empty = k3s stable
  channel. Pin it once you've validated a version, and bump deliberately.
- k3s defaults are kept (bundled Traefik, local-path storage, containerd).
  Change one thing at a time so you learn what each piece does.
- The cluster is a lab box you will break. That's the point. The VPS services
  (Kuma, and later Beszel) keep watching from outside while you do.
