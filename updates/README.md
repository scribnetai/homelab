# Fleet updates — check first, apply deliberately

The fleet's update workflow. Detection lives in Beszel; truth lives on the
host; application is a human decision per host, per window. Nothing in
this folder auto-applies anything — unattended application is a later,
per-class decision, not a default.

**Test bed:** the cloud VPS (standalone, nothing depends on it).
Rollout to the other apt hosts is phase 2: the check script is a single
self-contained file — copy it to a host and it works there.

## Getting the script onto a host

The checker is one self-contained file, and most hosts carry no repo
clone — so fetch it from this repo and verify its fingerprint before
running anything:

```
curl -fsSL https://raw.githubusercontent.com/scribnetai/homelab/main/updates/check-updates.sh -o /tmp/check-updates.sh
sha256sum /tmp/check-updates.sh
```

Compare the fingerprint against the trusted copy: the clone on
homelab-vps (`sha256sum ~/homelab/updates/check-updates.sh`, kept
current by `git pull`). If they differ, stop — the download is stale
or wrong. The pin is deliberately not printed here: it rotates with
every script change, and a stale printed hash is worse than none.
Then:

```
bash /tmp/check-updates.sh          # check (read-only)
bash /tmp/check-updates.sh --apply # apply (interactive)
```

## The workflow

1. **See (Beszel).** Open the hub's All Systems view. The Updates column
   is the fleet picture — but counts are *cached*: metrics refresh ~every
   minute, the update check runs on a slow cycle and at agent start.
   A yellow count is a prompt to look, not a fact.
2. **Verify (on the host).** Run the checker (distribution:
   "Getting the script onto a host", above):
   ```
   bash /tmp/check-updates.sh
   ```
   Read-only: it refreshes package metadata (installs nothing) and
   reports the simulated dist-upgrade — the count, the package names,
   and whether a reboot is already owed. **The host's output outranks
   the badge.** (Same number by hand: `apt-get -s dist-upgrade |
   grep -c "^Inst"`.)
   The checker reports a second number: **deferred by Ubuntu
   phasing**. Ubuntu rolls many updates out gradually; apt's bulk
   simulations defer those packages ("deferred due to phasing"),
   while Beszel's list-based count includes them. So the badge can
   legitimately read higher than the installable count — Beszel's
   total = installable + phased. Phased updates are a safety canary,
   not a failure: the standard is to let them land on schedule. (A
   named install forces past phasing when a specific fix genuinely
   can't wait: `apt-get install --only-upgrade <name>` — a deliberate
   override, never the default.)
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
   minute: expect the installable count at 0. The badge may still show
   the phased remainder for days — that's Ubuntu's rollout, not a
   failed patch. If the two ever disagree beyond the phased number,
   believe the host.

## Scope notes

- **apt hosts only** (Debian/Ubuntu/Proxmox). Windows (gaming PCs) is a
  separate lane and stays manual.
- **Containers are a different flow** — image pull + compose recreate,
  one service at a time, with a CHANGELOG entry; the host checker does
  not touch them. The Enshrouded game stack keeps its own updater.
- **The badge bug this prevents:** patching a host and watching Beszel
  still claim updates for hours is normal cached behavior, not a failed
  patch — step 5 exists so the board returns to truthful quickly.
