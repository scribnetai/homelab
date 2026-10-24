# VPS services — ops notes

The cloud VM runs the monitoring plane as Docker Compose services in this
folder: Uptime Kuma (up/down) and the Beszel hub (per-host metrics).
Both bind to localhost only; `tailscale serve` puts them on the tailnet
(443 -> Kuma, 8443 -> Beszel). Nothing listens publicly — the cloud
security group has zero inbound rules.

## Beszel agents

Agents are enrolled from the hub UI (Add System) with each machine's
**Tailscale IP**, port 45876, and installed with the hub-generated command
(binary + systemd service). Enrolled: both Proxmox hosts, the Enshrouded
VM, both k3s VMs, and the VPS itself. Agent pairing is by token — the
address in the system record is the hub's dial target (agents also phone
home outbound), so keep records on Tailscale IPs to match the
tailnet-only rule.

Container stats come from the Docker socket: hosts without Docker (the
k3s nodes run containerd) report host metrics only — their container
panels stay empty by design.

## Note: the "updates available" badge is cached

Beszel's metrics refresh about once a minute, but the pending-OS-updates
count does not: the agent re-checks on a slow cycle (hours) and whenever
it (re)starts. After patching a host, the badge can lag behind reality.
Force a re-check by restarting the agent on that host:

    systemctl restart beszel-agent      # as root (Proxmox hosts have no sudo)

Ground truth on the host itself (read-only simulation, changes nothing):

    apt-get -s dist-upgrade | grep -c "^Inst"     # 0 = fully patched

## Kuma watches the hub

The Kuma monitor for Beszel targets http://beszel:8090 over the shared
compose network — not the tailscale serve URL. A container on the same
host cannot use the serve URL: containers cannot resolve tailnet names
(the host resolver is bypassed, and the MagicDNS service address does
not answer bridge-sourced queries), and connections to the host's own
tailnet serve ports blackhole. A tailscaled failure is still covered:
every tailnet monitor flips at once.

## Backups

Nightly cron: backup.sh (04:15 ET) + backup-rotate.sh GFS tiers
(04:45 ET) — see "Backup & restore" in the root README. All tiers are
currently ON-box; an off-box copy target is a pending decision.
