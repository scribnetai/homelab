# Factorio 2.1 dedicated server on k3s — build guide

> **Public copy:** addresses, VM IDs, and host-specific details are placeholders (`<…>`); the full-detail working copy is kept private.


Companion to `manifests/factorio.yaml`. **Status: validated end to end in a disposable test run
2026-10-25 (`factorio/TEST-RUN.md`); the live deployment is a
separate, later step.** Decisions locked 2026-10-25: k3s (not a
dedicated VM), pinned to the worker node (k3s-agent), LAN first pass,
external friends in stage 2, Space Age for everyone, and the world is
crafted in his client and uploaded — never generated from a server
preset.

## Why k3s here, a VM for Enshrouded

Enshrouded is a Windows `.exe` under Wine that wants ~16 GB — a VM
isolates that tax. Factorio is the opposite: a native Linux headless
binary in one small official container (`factoriotools/factorio`,
pinned **2.1.23**), all state in a single directory. That is exactly
what a StatefulSet + Longhorn volume is for. Factorio is also
effectively single-threaded, so it needs one good core and a few GB —
it fits the current nodes with no resize.

Version discipline matters this month: 2.1 went stable 2026-10-23
and **2.1 saves/blueprints cannot be downgraded to 2.0**. A fresh
2.1 world has no migration risk. The image tag is pinned so a
mid-week patch can never strand players on mismatched clients.

## Build order (gates, not suggestions)

0. **Terraform drift gate — no TF changes for Factorio, prove it.**
   No new VM is created and no resize is needed (Factorio fits the
   current nodes), so the deploy itself is pure
   `kubectl`. But the nodes *are* TF-managed, so first,
   on the gaming PC in `k8s/terraform`: `terraform plan`
   Checker: **"No changes"** — the Oct 24 resize state, matching.
   Anything else = stop; the working copy and the live VMs disagree
   and we reconcile that first, separately from this build.
   Known wrinkle: keep the repo's Terraform in sync with any
   VM resize done outside it — a stale sizing in git makes a fresh
   clone plan a shrink back. Run TF from the copy whose state and
   sizing match the live VMs, and land sizing edits (+ CHANGELOG)
   in the repo in the same pass.
1. **Label the node.** `kubectl label node k3s-agent example.com/game-server=true`
   Checker: `kubectl get nodes -L example.com/game-server` → `true`
   on exactly one node (the agent).
2. **Apply.** `kubectl apply -f manifests/factorio.yaml`
   Checker: `kubectl -n factorio get pods,pvc` → pod `factorio-0`
   Running, PVC `factorio-data-factorio-0` Bound on `longhorn-rep2`,
   20Gi.
3. **First boot = throwaway world.** The image generates/loads a
   default save and proves the stack end to end.
   Checker: `kubectl -n factorio logs statefulset/factorio -f` →
   server reports the map loaded and running; then a **real in-game
   LAN join** from the gaming PC to `<agent-lan-ip>:34197`
   (k3s-agent's LAN IP). The join is the test, not the log line.
4. **Set the server identity in-pod.** First boot generated
   `/factorio/config/server-settings.json` on the PVC. Set name,
   description, `visibility` (public/lan both false for
   direct-connect-only), and the **game password** there
   (`game_password` — the image has no env var for it; it lives
   only in that file, and a change needs a pod restart to take
   effect). That real file never enters git — same rule as
   PocketBase's superuser. **Admins (decided 2026-10-25): flat
   trust** — every invited player is a game admin, listed by exact
   Factorio username in `/factorio/config/server-adminlist.json`
   (same names as the whitelist, which remains the access gate);
   no tiered in-game privileges. **Mechanism:**
   `factorio/configure-server.ps1` (bash twin alongside) — run at
   deploy time, it prompts locally for the password (hidden, twice),
   the server name/description (current values as defaults; the
   first-boot settings carry the image's placeholder text, which is
   what the game client's Continue button displays), and the admin
   usernames, edits the PVC files via the helper-pod
   pattern while the server is scaled to 0, backs up the prior
   settings to `server-settings.json.bak` on the PVC, and verifies
   by password LENGTH + list readback — the password value is never
   printed, passed as an argument, or stored anywhere but Dashlane
   and the PVC.
   **Finding a Factorio username** (needed for every adminlist /
   whitelist entry; the match is exact, character for character —
   a typo locks that player out): the authoritative value is the
   account name the game presents to servers, readable from
   PowerShell without launching anything:
   `(Get-Content "$env:APPDATA\Factorio\player-data.json" -Raw | ConvertFrom-Json).'service-username'`
   In-game equivalents: the username shown at the main menu when
   logged in, or `/players` in the console (`~`) of any loaded
   world. If `service-username` is empty (account never linked
   in-game), the `/players` name is the identity that counts.
   Collect each friend's username the same way before the live
   deploy — do not guess from Steam/Discord display names.
   Checker: `kubectl -n factorio exec factorio-0 -- cat /factorio/config/server-settings.json | Select-String name,visibility` (from PowerShell) shows your values, passwords redacted in anything you paste back.
5. **Upload the real world** (next section), replacing the throwaway.
6. **Backups + monitoring** (stage 1.5, before external players):
   **DECIDED 2026-10-25 (his call): Layer 1 only for now** — the
   upload script's in-PVC pre-change backups are the backup story
   at live launch. Deferred until he reopens them: Longhorn
   scheduled snapshots of the volume, an off-box pull of `saves/`
   into GFS tiers (verified by opening the first archive), and the
   Kuma Push checker that asks the server over RCON from inside
   the pod (`kubectl exec ... rcon /players`, same pattern as
   Enshrouded's A2S push checker).

## The save-upload flow (the integrated part)

You choose every setting in the real game UI — map generation,
resource sliders, enemy settings, Space Age options — and the
dedicated server runs *that exact world*.

1. **Craft it locally.** In your Factorio client (2.1, Space Age):
   New Game → pick your settings → generate → save immediately with
   a clean name, e.g. `scribnet-space-age` (letters/digits/dashes —
   it becomes a filename and a `SAVE_NAME`). You can play it first
   or upload it untouched; the server continues from the save.
   Save location (Windows): `%appdata%\Factorio\saves\<name>.zip`
   — paste that path into File Explorer's address bar to find it.
2. **Upload it with the script in this folder** (from PowerShell on
   the gaming PC, kubeconfig already set up). PowerShell rules for
   every script in this kit (learned live on the 2026-10-25 test
   run, his call): scripts are **ASCII-only** — Windows PowerShell
   5.1 reads a BOM-less file as ANSI, and one UTF-8 em dash in a
   string decodes to a stray quote that breaks the parser before
   anything runs. And **no `-ExecutionPolicy Bypass`** anywhere:
   the supported setup is a one-time, per-user
   `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
   (no admin); for a copy downloaded from a browser/chat, verify
   its SHA-256 against the published hash, then `Unblock-File`
   that one file.
   ```powershell
   .\factorio\upload-save.ps1 -Save "$env:APPDATA\Factorio\saves\scribnet-space-age.zip" -CleanThrowaway
   ```
   What the script does, in order — no step is a black box:
   - Validates the `.zip` really is a Factorio save (contains a
     `level.dat` entry) before touching the cluster.
   - Scales the StatefulSet to 0, so no autosave can race the upload
     and become "newest" instead of your save.
   - Starts a one-shot `busybox` helper pod mounting the **same**
     Longhorn PVC, pinned to k3s-agent (a ReadWriteOnce volume can
     only attach on one node; the game pod is stopped and on that
     node, so this is clean). Helper pod, not `kubectl cp` into the
     game container — this path does not depend on the game image
     containing `tar`, which `kubectl cp` requires.
   - **Backs up the current saves first** (added 2026-10-25, his
     request): every `.zip` in `/data/saves/` is copied to
     `/data/backups/upload-<timestamp>/` on the same PVC and the
     copy count is verified — before anything is deleted or
     overwritten. A pre-change safety net on the same volume, not
     a substitute for the off-box Longhorn/GFS backup layer.
   - Copies the save into `/data/saves/`, and with
     `-CleanThrowaway` first removes the step-3 throwaway
     `_autosave*.zip` files (it lists them and asks before deleting).
   - Lists `saves/` sorted by time and **verifies your save is the
     newest file** — that ordering is what `LOAD_LATEST_SAVE=true`
     keys on (the image's documented pattern for existing saves:
     newest file wins). If it isn't newest, the script stops and
     says so instead of starting the wrong world.
   - Deletes the helper pod, scales back to 1, and tails the log.
   Checker at the end: the log shows your save being loaded, and the
   in-game join shows *your* map, not the throwaway.
3. **Mods, if any.** Space Age's own mods are built into the DLC —
   nothing to upload. If your crafted save enables any *portal* mods,
   they must exist in `/factorio/mods` at matching versions or the
   load fails: `.\factorio\upload-save.ps1 -Mods "$env:APPDATA\Factorio\mods"` uploads that folder through the same helper pod.
   One match-the-save rule: if you crafted the save **without
   Quality**, tell Sparky before first boot — the manifest's
   `DLC_SPACE_AGE` becomes `"space-age elevated-rails"` so the
   server doesn't re-enable a mod the world was generated without.

Rollback is trivial: saves are just files. Re-run the script with an
older `.zip` (it becomes newest by upload time) and restart — or keep
the GFS archives from step 6 of the build order.

## Stage 2 — external friends (definite, designed for now)

**DECIDED 2026-10-25: Option A (Tailscale node-share) is the plan of
record.** The full stage-2 runbook — share steps, the paste-ready
ACL grant, and the positive/negative verification tests — is
`factorio/tailscale-friends-access.md`. Option B (port forward)
remains the prepared fallback if a friend can't/won't run Tailscale.

The phase-1 `hostPort` bind listens on the node itself, so **both**
options below work with zero manifest changes. They can even run at
the same time for different friends.

### Option A — Tailscale node-share (DECIDED — plan of record)
- Each friend installs Tailscale (free personal tier), you share
  **only the k3s-agent machine** from the Tailscale admin console,
  and an ACL **grant** scopes them to exactly one thing:
  `"ip": ["udp:34197"]` against the agent node. Nothing else on that
  VM (SSH, kubelet) is reachable to them — a shared node can only
  accept incoming connections, and the grant narrows it to the game
  port. This pattern is proven specifically for Factorio: players
  connect to the node's Tailscale name/IP `:34197` in-game.
- Pros: zero public exposure, no router change, works even behind
  CGNAT (e.g. Starlink), stable 100.x address (your dynamic home IP
  stops mattering).
- Cons: every friend must install one more app; if a connection
  falls back to a DERP relay instead of going direct, latency rises
  (checker on the VM: `tailscale status` shows `direct` vs `relay`
  per peer — the Factorio write-ups report direct connections
  punching through multi-layer home NAT fine).

### Option B — Port forward (fallback, only if Option A fails for someone)
- Forward **UDP 34197 only** on the router (Deco) to
  `<agent-lan-ip>` (k3s-agent). Friends direct-connect to
  `<home-public-IP>:34197`.
- Preconditions to verify in the stage-2 session, in order:
  1. The WAN address on the router **equals** the public IP a
     what's-my-IP check shows (mismatch = CGNAT upstream, forwarding
     can never work — fall back to Option A). A line with a real
     public WAN address forwards fine; a CGNAT line (e.g. satellite)
     never will.
  2. A DDNS name (Deco's built-in DDNS or similar) — your public IP
     is dynamic and *will* rotate; friends need a stable hostname.
  3. Security gates **before** the forward goes live: game password
     set (step 4), whitelist **on** with each friend's Factorio
     username in `server-whitelist.json`, visibility public/lan
     false (direct-connect only, never in the public server
     browser), and 2.1.23 kept current for fixes. RCON stays
     unexposed in all cases — it is a full console and never gets a
     forward, ever.

### Option C — Tunnel service (playit.gg etc.), only if A and B fail
No router access needed, adds a third party and their relay latency.
Parked unless CGNAT blocks B and a friend won't install Tailscale.

## Security review (standing pass)

- Only UDP 34197 ever faces outward, and only via one of the stage-2
  doors above. RCON (full remote console) has no Service, no
  hostPort, no forward — admin is `kubectl exec` over your existing
  authenticated, tailnet-carried kubeconfig.
- Container runs non-root (image UID 845), `privileged: false`,
  `allowPrivilegeEscalation: false`. Remaining hardening (capability
  drops, read-only rootfs) is deliberately deferred until the vanilla
  pod is proven — one knob at a time, per the fleet's own lesson.
- No secrets in this repo: game/RCON passwords live only in files on
  the PVC; a future factorio.com token (for auto mod updates) would
  be a k8s Secret created in-cluster, never a manifest value.
- Longhorn replicates the world to both nodes (rep2) — a node loss
  degrades the cluster but the save survives. That is replication,
  not backup. Backup scope as decided 2026-10-25: Layer 1 only
  (the upload script's in-PVC pre-change backups); off-box GFS
  archives are deferred until he reopens them (see stage 1.5).

## Operations notes — proven on the 2026-10-25 test run

The full disposable test run (gates T0–T8, `factorio/TEST-RUN.md`)
passed end to end: deploy, crafted-save upload, password/admin
configure, join, pod-kill resilience, clean teardown. Lessons
that generalize beyond this build:

- **PowerShell 5.1 native-argument traps (all hit live):** (1) it
  strips inner double quotes from no-space arguments — JSON and
  other payloads travel as FILES (manifest + `kubectl apply -f`),
  never inline; in-pod awk with quoted programs died the same way
  and was replaced by copying the file out and parsing locally
  with `ConvertFrom-Json`. (2) `kubectl cp` parses `pod:path` by
  colon — a Windows drive-letter path reads as a remote spec, so
  every copy runs from inside the folder with relative `.\`
  paths. (3) With `$ErrorActionPreference = "Stop"`, a native
  command exiting nonzero through redirected stderr is a
  terminating `NativeCommandError` — expected-failure commands end
  in `exit 0` in-pod, or run under a scoped `Continue`. (4)
  `@(ConvertFrom-Json ...)` wraps the parsed array as a single
  element (array-of-array) — flatten to strings before use.
- **The manifest contains the Namespace.** `kubectl delete -f
  factorio.yaml` deletes the namespace, whose termination cascades
  to everything in it — including the PVC (the Longhorn volume is
  reaped with it). Correct for test teardown; on the LIVE server,
  never delete the namespace or the PVC — work object-by-object.
- **Helper pods are bare pods.** A node reboot mid-helper leaves a
  Failed pod that never self-heals; the fix is `kubectl delete
  pod <helper>` and rerun the script. Data on the PVC is never at
  risk from this — the pod is a window, not the storage.
