# Fleet updates — check first, apply deliberately

The fleet's update workflow. Detection lives in Beszel; truth lives on the
host; application is a human decision per host, per window. Nothing in
this folder auto-applies anything — unattended application is a later,
per-class decision, not a default.

**Test bed:** the cloud VPS (standalone, nothing depends on it).
Rollout to the other apt hosts is phase 2: the check script is a single
self-contained file — copy it to a host and it works there.

## The workflow

1. **See (Beszel).** Open the hub's All Systems view. The Updates column
   is the fleet picture — but counts are *cached*: metrics refresh ~every
   minute, the update check runs on a slow cycle and at agent start.
   A yellow count is a prompt to look, not a fact.
2. **Verify (on the host).** Run the checker:
   ```
   ./check-updates.sh
   ```
   Read-only: it refreshes package metadata (installs nothing) and
   reports the simulated dist-upgrade — the count, the package names,
   and whether a reboot is already owed. **The host's output outranks
   the badge.** (Same number by hand: `apt-get -s dist-upgrade |
   grep -c "^Inst"`.)
3. **Decide (window + order).** Patch one blast radius at a time:
   - **Cloud VPS** — standalone; patch in any calm window.
   - **Proxmox hosts** — never back-to-back without a health check
     between them. The k3s control plane (etcd) is a VM on proxmox, and
     Longhorn keeps its 2 replicas one-per-node: one host down is
     survivable, two is an outage. Patch host -> verify cluster, VMs
     and Longhorn healthy -> patch the other.
   - **k3s / Enshrouded / Hermes VMs** — patch when their workload is
     quiet (for the game server: when it's empty, the same ethic as its
     own dedicated-server updater).
   - A pending **kernel / pve-kernel** update means a reboot belongs in
     the same window — check step 2's reboot line before you start.
4. **Apply.** `./check-updates.sh --apply` — interactive apt (you see the
   plan and confirm; no `-y` in this phase by design). If the reboot
   line says one is required afterwards, reboot in the same window.
5. **Confirm.** Every run of the script (check or apply) restarts
   `beszel-agent`, which forces the hub badge to refresh within a
   minute: expect "Up to date" and a host re-check of 0. If the two
   ever disagree, believe the host.

## Scope notes

- **apt hosts only** (Debian/Ubuntu/Proxmox). Windows (gaming PCs) is a
  separate lane and stays manual.
- **Containers are a different flow** — image pull + compose recreate,
  one service at a time, with a CHANGELOG entry; the host checker does
  not touch them. The Enshrouded game stack keeps its own updater.
- **The badge bug this prevents:** patching a host and watching Beszel
  still claim updates for hours is normal cached behavior, not a failed
  patch — step 5 exists so the board returns to truthful quickly.
