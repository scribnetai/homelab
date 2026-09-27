# Containers & Kubernetes — the mental models

## Containers are not tiny VMs (but close enough to start)

A VM virtualizes hardware: each one carries a full guest OS, virtual devices,
its own kernel. Gigabytes of disk, seconds-to-minutes to boot.

A container shares the host's kernel and packages just the app plus its
dependencies, isolated with kernel namespaces (what it can see) and cgroups
(what it can use). Megabytes of disk, milliseconds to start. You can run
dozens of containers on a NUC that would choke on a dozen VMs.

The key consequence: **the container image (OCI format) is the portable unit**.
The same Immich or AdGuard Home image runs under Docker Compose on the VPS,
under k3s on the NUCs, under EKS at work. The image doesn't care — the
*orchestrator* is what differs.

## Docker Compose = the standalone ESXi host

Compose defines and runs containers on **one machine**: app + database + cache,
wired together, started with one command. It's the equivalent of a single
ESXi host where you hand-manage each VM. Simple, predictable, and completely
adequate for single-host workloads — which is why Kuma lives on the VPS this
way.

## Kubernetes = vCenter for containers

Kubernetes doesn't replace containers; it **orchestrates** them across machines:

| Kubernetes concept | Datacenter analogue | What it actually is |
|---|---|---|
| Control plane (API server, scheduler, etcd) | vCenter | The brain: you declare desired state, it converges reality |
| Worker node (kubelet + container runtime) | ESXi host | Runs the workloads |
| Pod | A VM | Smallest deployable unit — one or more containers sharing network/storage |
| Deployment | VM template + "keep N running" | Desired replica count, rolling updates, self-healing |
| Service | A VIP | Stable virtual IP + DNS in front of ephemeral pods |
| Ingress | L7 load balancer | HTTP routing to services by host/path (k3s ships Traefik for this) |
| PersistentVolumeClaim | "Give me a VMDK" | A storage request; the cluster provisions the backing volume |
| ConfigMap / Secret | Guest customization / vault | Config and credentials injected into containers |
| Namespace | A folder / resource pool | Tenancy and blast-radius boundary |
| Helm chart | An OVA | A packaged, parameterized app install |

Two differences from the VMware world worth internalizing:

1. **No vMotion magic.** When a node dies, Kubernetes doesn't live-migrate —
   it *restarts* the containers elsewhere. That's why cloud-native apps are
   stateless and state lives in volumes or external databases. The pod is
   cattle, not a pet.
2. **Desired state, not procedures.** You never SSH in and start things. You
   write YAML describing what *should* exist; controllers loop forever making
   reality match. GitOps (ArgoCD) is just taking that idea to its conclusion:
   the repo *is* the desired state.

## When is Kubernetes worth it over Compose?

- Workloads span **multiple hosts** and you want scheduling, not manual
  placement.
- You want **self-healing** (dead pod → rescheduled) and **zero-downtime
  rolling updates** without scripting them yourself.
- You want **service discovery** (pods finding each other by DNS name) and
  declarative networking/storage.

The cost: etcd, CNI networking, and storage are now distributed systems you
operate. That's the learning curve — and the resume line.

## One-line version

**Compose runs containers. Kubernetes runs a platform made of containers.**
