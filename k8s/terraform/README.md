# k3s Proxmox VMs — Terraform

Builds the two k3s nodes from `k8s/README.md` (server on NUC-1, agent on NUC-2)
as full clones of one Ubuntu 24.04 cloud-init template. Run Terraform from your
PC (native Windows binary or WSL both work).

## 0. Prereqs

- Terraform >= 1.6 installed.
- A Proxmox API token: **Datacenter → Permissions → API Tokens** → Add (give it
  to a user with admin on the two nodes, e.g. `root@pam`). Copy the secret once.
- Storage: the cloud-init datastore (`local` by default) must allow the
  **Snippets** and **Disk images** content types (Datacenter → Storage →
  `local` → Edit → Content). Snippets hold the cloud-init user-data; the
  generated cloud-init ISO is stored as a disk image. Both fail at apply
  time if the content types are missing.
- Node SSH access for the provider: the cloud-init snippet uploads go over
  SSH, not the API. Either set `PROXMOX_VE_SSH_USERNAME` /
  `PROXMOX_VE_SSH_PASSWORD` (step 2), or load your key in ssh-agent with
  the matching public key authorized for root on the nodes.

## 1. Build the golden template

The template is what both VMs clone. Each Proxmox node needs a local copy —
the provider runs the clone on the target node, so with local storage a
template on one node cannot serve the other:

```bash
scp build-template.sh root@<proxmox-node-1>:/tmp/
ssh root@<proxmox-node-1> "bash /tmp/build-template.sh"
scp build-template.sh root@<proxmox-node-2>:/tmp/
ssh root@<proxmox-node-2> "TEMPLATE_ID=9001 bash /tmp/build-template.sh"
```

In a cluster the copies need distinct VMIDs (9000, 9001, ...) matching the
per-node `template_id` in `main.tf`'s `locals.nodes`. (Separate standalone
nodes may each reuse 9000.)

This downloads the Ubuntu 24.04 cloud image, imports it to `local-lvm`, wires up
the cloud-init drive + serial console + qemu guest agent, and converts the VM
(9000 by default) into a template. Re-run any time you want to refresh the
base image.

## 2. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: endpoint, IPs, ssh key
```

`terraform.tfvars` is yours and is never committed (nothing secret belongs in
git — same rule as every other credential in this repo).

```bash
export PROXMOX_VE_API_TOKEN='root@pam!terraform=YOUR_TOKEN_SECRET'
export PROXMOX_VE_SSH_USERNAME='root'
export PROXMOX_VE_SSH_PASSWORD='YOUR_SSH_PASSWORD'
```

The SSH pair is the provider's second auth leg — it uploads the cloud-init
snippets to the nodes. All three variables live only in your shell session;
none of them ever go in a file.

## 3. Apply

```bash
terraform init
terraform apply
```

Proxmox assigns VM IDs automatically; `terraform output` shows names, nodes, IDs,
and lab-net IPs.

## 4. Finish the nodes by hand (2 minutes)

1. `tailscale up` on each VM (SSH in via the lab-net IP from the output, or use
   the Proxmox console). This is deliberately manual — no Tailscale auth keys
   are stored anywhere.
2. **Snapshot both VMs now** — Datacenter → node → VM → Snapshots → Take
   Snapshot. This is your rewind point: when you inevitably break the cluster
   learning, roll back here in seconds instead of rebuilding.
3. Continue with the bring-up in [`k8s/README.md`](../README.md):
   `sudo bash k3s-install.sh server` on k3s-server, then the agent join.

## Files

| File | What it is |
|---|---|
| `versions.tf` | Terraform + `bpg/proxmox` provider pins |
| `variables.tf` | Everything you'd ever tweak (nodes, IPs, sizes, datastores) |
| `main.tf` | Snippet files + the two VM resources (one `for_each` map) |
| `outputs.tf` | Names, nodes, IDs, IPs after apply |
| `terraform.tfvars.example` | Copy to `terraform.tfvars`, fill in yours |
| `files/user-data.yaml.tftpl` | Cloud-init: user, SSH keys, qemu-guest-agent, Tailscale |
| `build-template.sh` | One-time golden-template build (runs on a Proxmox node) |

To resize a node later, change `locals.nodes` in `main.tf` and re-apply. To add a
third node (second worker), add one map entry.
