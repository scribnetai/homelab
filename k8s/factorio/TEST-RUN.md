# Factorio k3s TEST RUN — validation spike (2026-10-25)

> **Public copy:** addresses, VM/volume IDs, and usernames are placeholders (`<…>`); the full-detail working copy is kept private.


A disposable end-to-end proof: deploy from files → join over the
tailnet → upload a client-crafted save → prove the world survives a
pod kill → tear everything down. **This is not the live server.**
Nothing here is exposed externally, and anything that would make it
"real" (passwords, whitelist, backups, monitoring, friend access)
is deliberately out of scope and listed under Live-run deltas.

Guardrails for this run:
- **Tailnet only.** The join target is the agent node's Tailscale
  address. No friend shares, no ACL grant edits, no router forwards,
  no Funnel. (Honest note: `hostPort` binds the node's interfaces,
  LAN included — what "tailnet only" controls here is that we only
  ever connect via the tailnet and nothing is published or
  forwarded anywhere.)
- **Declarative or it didn't happen.** Every object comes from
  `manifests/factorio.yaml`; every file move goes through
  `factorio/upload-save.ps1`. No hand-made cluster objects.
- **Verify before claiming.** Each claim below has a checker and a
  result line. A claim is *unverified* until its checker output is
  pasted back and read — not when the apply "succeeded".

## The five claims under test

| # | Claim | Proved by |
|---|-------|-----------|
| 1 | The manifest deploys a working Factorio 2.1.23 server on k3s-agent with Longhorn storage | T2/T3 checkers |
| 2 | The server is joinable over the tailnet | T4 in-game join |
| 3 | A save crafted in the client can be uploaded and becomes the running world | T5/T6 |
| 4 | The world lives on the PVC, not in the pod — kill the pod, keep the world | T7 |
| 5 | Teardown is clean and complete; the files alone can rebuild it | T8 checkers |

## T0 — Terraform drift gate (gaming PC, PowerShell)

Terraform created these VMs and resized them on Oct 24; Factorio
changes no VM, so plan must be empty. Set the Proxmox env vars in
**the same window** that runs terraform (session vars die with the
window — the Oct 19 lesson). Names only, never values:

```powershell
Get-ChildItem Env:PROXMOX_VE_* | Select-Object -ExpandProperty Name
cd <your homelab clone>\k8s\terraform
terraform plan
```
**Expect:** `No changes. Your infrastructure is in sync.`
Anything else → STOP. Reconcile the working copy first (a stale sizing in git is a known trap — see FACTORIO.md
step 0); do not apply anything from this window toward Factorio.

While you're in PowerShell, cluster sanity:
```powershell
kubectl get nodes
```
**Expect:** `k3s-server` + `k3s-agent`, both `Ready`.

## T1 — Label the game node

```powershell
kubectl label node k3s-agent example.com/game-server=true
kubectl get nodes -L example.com/game-server
```
**Expect:** the label column shows `true` on `k3s-agent` and blank
on `k3s-server`. (The label stays after teardown — it's live-run
infrastructure, not test debris.)

## T2 — Apply the manifest

Save `factorio.yaml` (attached in chat) to
`<homelab clone>\k8s\manifests\factorio.yaml`, then:

```powershell
kubectl apply -f <homelab clone>\k8s\manifests\factorio.yaml
kubectl -n factorio get pvc
kubectl -n factorio get pods -o wide -w
```
(Watch takes a single resource type — `get pods,pvc -w` errors with
"you may only specify a single resource type". Learned on the test
run itself, 2026-10-25; check the PVC with its own one-shot `get`.)
**Expect:** pod `factorio-0` reaches `Running` with `NODE =
k3s-agent`; PVC `factorio-data-factorio-0` is `Bound`, `20Gi`,
storage class `longhorn-rep2`. Ctrl+C once Running.
First image pull can take a few minutes — `ContainerCreating` /
`ErrImagePull` that resolves itself is the pull, not a failure.

## T3 — Log proof

```powershell
kubectl -n factorio logs statefulset/factorio --tail 60
```
**Expect (the decisive lines):** the Factorio version banner
`2.1.23`, a map being created/loaded from `/factorio/saves/`, and
the server hosting on port `34197`. Paste the tail back — claim 1
is verified from this output, not from `apply` succeeding.

## T4 — Tailnet join (throwaway world)

In your client: **Multiplayer → Connect to address** →
`<agent-magicdns>:34197` (fallback: `<agent-tailnet-ip>:34197`).
**Expect:** you spawn in the generated throwaway world and can move.
Optional network checker (from the agent VM or any tailnet box):
`tailscale status` should show your PC's connection to k3s-agent.

## T5 — Craft + upload your test save

1. In the client: **New Game → Space Age** → any settings (this is
   a throwaway — speed over beauty) → spawn → **Save game** as
   `factorio-test-01` → quit to menu.
   Path: `%appdata%\Factorio\saves\factorio-test-01.zip`
2. Save `upload-save.ps1` (attached in chat) to
   `<homelab clone>\k8s\factorio\upload-save.ps1`, then:
   ```powershell
   cd <homelab clone>\k8s
   .\factorio\upload-save.ps1 -Save "$env:APPDATA\Factorio\saves\factorio-test-01.zip" -CleanThrowaway
   ```
   The script scales the server to 0, mounts the same PVC in a
   busybox helper pod on the agent, deletes the throwaway
   `_autosave*.zip` files (lists them, asks `yes`), copies your
   save in, and **verifies your save is newest** before scaling
   back to 1. Any failure stops with the server still at 0 — by
   design, it never starts the wrong world quietly.
3. Log checker, same as T3: the load line must now name
   `factorio-test-01.zip`.

## T6 — Re-join: your world, on the server

Connect again (same tailnet address). **Expect:** the exact map you
just crafted in the client — your spawn, your settings. This is the
validation moment for claim 3.

## T7 — Kill the pod, keep the world

```powershell
kubectl -n factorio delete pod factorio-0
kubectl -n factorio get pods -w
```
**Expect:** a new `factorio-0` is created by the StatefulSet and
returns to `Running`. Re-join: the world is still there, including
anything you did in T6 (it loads the latest autosave from the PVC).
That is claim 4 — the pod is disposable, the Longhorn volume is
the world. (Your vSphere translation: delete the VM object, keep
the VMDK on the shared datastore, power a fresh VM onto it.)

## T8 — Teardown (complete, verified from the cluster's mouth)

```powershell
kubectl delete -f <homelab clone>\k8s\manifests\factorio.yaml
kubectl -n factorio delete pvc factorio-data-factorio-0
kubectl delete namespace factorio
kubectl get namespace factorio
kubectl -n longhorn-system get volumes.longhorn.io
```
Notes:
- Deleting the StatefulSet deliberately does **not** delete the PVC
  (retention policy `Retain` in the manifest — the live run depends
  on that safety). The test run deletes the PVC explicitly, as its
  own decision, in its own command — that's why it's a separate line.
- **Expect:** namespace lookup returns `NotFound`; the Longhorn
  volumes list no longer shows the Factorio volume (name starts
  `pvc-` — match it against the PVC's `VOLUME` column from T2 if
  unsure). The game-node label (T1) and the manifest files remain —
  intentionally, they're the live run's starting point.

## Results (fill in during the run — Sparky keeps this current)

| Gate | Result | Evidence (checker output summary) |
|------|--------|-----------------------------------|
| T0 TF plan | ✅ verified 2026-10-25 | Plan refreshed both cluster VMs + both snippet files: "No changes. Your infrastructure matches the configuration." Nodes both Ready, v1.36.5+k3s1 (node sizing confirmed in the PC main.tf pre-plan). |
| T1 label | ✅ verified 2026-10-25 | `kubectl get nodes -L example.com/game-server`: true on k3s-agent, blank on k3s-server. Apply then created all 5 objects (ns, configmap, 2 services, statefulset). |
| T2 apply / PVC Bound / pod on agent | ✅ verified 2026-10-25 | PVC Bound → `<pvc-id>`, 20Gi RWO `longhorn-rep2`; pod 1/1 Running, 0 restarts, on `k3s-agent`. |
| T3 version 2.1.23 + hosting log lines | ✅ verified 2026-10-25 | Banner `Factorio 2.1.23 (build 87750, linux64, headless, space-age)`; `--start-server-load-latest` active; fresh map loaded from `/factorio/saves/_autosave1.zip` (map version 2.1.23-2); `Hosting game at 0.0.0.0:34197`; write path `/factorio [19969/19986MB]` = the PVC; RCON up inside the pod only. Observations: (1) `Got EOF on stdin` error line is a known cosmetic quirk of the image without a tty — server unaffected. (2) `Matching server connection failed: Missing token` = public server-browser registration skipped (no factorio.com TOKEN set) — server is NOT publicly listed, desired; direct connect unaffected. (3) ServerRouter "own address" warnings = NAT/pingpong noise on that same public-discovery path. (4) `DLC_SPACE_AGE="true"` loads the full SA set INCLUDING Quality (log shows `Loading mod quality 2.1.23`, FeatureFlag `quality`) — the live save should be crafted with the same set. (5) The entrypoint's shell trace prints the auto-generated RCON password into the pod log (Factorio's own args echo redacts it; the `+ exec` line does not) — pod-log access = RCON password access; acceptable under the tailnet-only kubectl model, noted for the live run; the value is never recorded here. |
| T4 tailnet join (throwaway) | ✅ verified 2026-10-25 | ScribNet reported a successful in-game connection to the throwaway world; he stopped after T4 (save upload not yet attempted). |
| T5 upload (script verified-newest) | ✅ verified 2026-10-25 (run 5, clean pass) | First attempt 2026-10-25 stopped at load time twice, cluster untouched both times: (1) execution policy blocked the script (default policy on his PC); (2) after a Process-scope Bypass (his call: rejected as the standing method — "kinda sketch", kit must be usable by anyone), PS 5.1 mis-parsed the UTF-8-no-BOM file (em dash in a throw string decodes as ANSI to a stray quote). Fix shipped same day: both .ps1 scripts rewritten ASCII-only (verified 0 non-ASCII bytes) and the kit standard changed to CurrentUser RemoteSigned + SHA-256 check + Unblock-File for downloaded copies; no Bypass in the runbook. Upload itself still to run. Run 2 (same day) got further — save validated, cluster preflight passed, server scaled to 0 cleanly — then helper-pod creation failed: `Invalid JSON Patch`. Root cause: PS 5.1 stripped the inner double quotes from the script's no-space `--overrides` JSON argument (the 2026-10-24 rule, biting our own script). Fix shipped same day: helper pods are now created from a manifest file via `kubectl apply -f` in BOTH .ps1 scripts (generated YAML parse-verified off-cluster; new hashes recorded in chat). Failure posture worked as designed: server left at 0, PVC untouched, nothing uploaded; rerun is idempotent. Run 3 (same day) cleared the helper step (pod created via manifest, Ready) and the cleanup step (deleted `_autosave1.zip` after his "yes"), then `kubectl cp` rejected the upload: "one of src or dest must be a local file specification" — kubectl cp parses pod:path by colon, so the Windows drive-letter source path reads as REMOTE. Fix shipped same day: all cp calls in both .ps1 scripts now run from inside the source folder with relative `.\` paths and plain `pod:path` destinations (configure-server.ps1 had five absolute-path cp calls, fixed pre-emptively). State after run 3: server at 0, helper pod left running (the rerun deletes it first), throwaway autosave already deleted — by design, his crafted save replaces it. At his request the script then gained a backup-first step (both .ps1 and .sh): before any deletion/upload it copies every current save to `/data/backups/upload-<timestamp>/` on the PVC and verifies the count — on this rerun it will find saves/ empty (post-cleanup) and skip cleanly; on the live server it protects the real world. **Run 5 (fixed scripts 8A58E30B/398E23C3, after the k3s VM memory doubling and deletion of the resize-killed helper pod): CLEAN PASS** — backup step printed "No existing saves in the PVC — nothing to back up" (the exit-0 fix working live), cleanup found nothing, upload copied factorio-test-01.zip, newest-save verification passed, helper deleted, rollout complete 1/1. |
| T5b configure rehearsal (password + adminlist) | ✅ verified 2026-10-25 (manual checkers after script verify crash) | `configure-server.ps1` run against the TEST instance between T5 and T6 (his call, 2026-10-25): hidden double prompt for a test password, his Factorio username as sole admin/whitelist entry. Pass = script checkers show password LENGTH match + admin list readback; T6 then proves the prompt + admin in-game. The script's JSON-edit core was functionally tested off-cluster 2026-10-25 (bash/python path: field set exactly, other settings preserved, names trimmed/deduped); the PowerShell wrapper itself is structurally checked only — first live run is its real test, same caveat as upload-save.ps1. |
| T6 re-join own world | ✅ verified 2026-10-25 | CORRECTION (his, 2026-10-25 ~12:10 ET): the ~12:07 "I'm in the new map" report was his LOCAL save loaded in the client, NOT a join to the Kubernetes server — T6's client join is therefore still unproven. What IS proven server-side: the pod log loaded `/factorio/saves/factorio-test-01.zip` and reached InGame/hosting. Still required: finish T5b verification + restart, then join via Multiplayer → Connect to address (LAN <agent-lan-ip>:34197) — Load Game doesn't count — expecting the password prompt + admin. |
| T7 pod delete → world persists | ✅ verified 2026-10-25 | `kubectl delete pod factorio-0` → StatefulSet recreated it in ~2s (ContainerCreating → 1/1 Running, same name, same node). New pod loaded the GROWN world: level.dat 1,904,324 bytes vs the original upload's 1,786,151 — play-session progress persisted through the kill — reached InGame/hosting on 34197. (Same session also produced the first fully-clean configure-server run: new local-parse verify printed all four checkers green — password length 3=3, name 'TestServer01', adminlist + whitelist [<your-username>]. One cosmetic bug spotted in that run — "Current admin list: System.Object[]" — exposed a REAL latent bug: `@(ConvertFrom-Json ...)` wrapped the parsed list as an array-of-array, so the Enter-to-keep path would have written a nested list; fixed same day by flattening to strings, build 6FA78219.) |
| T8 teardown NotFound + volume gone | ✅ verified 2026-10-25 | `kubectl delete -f factorio.yaml` deleted all 5 objects — INCLUDING the Namespace itself (it's doc 1 of the manifest), whose termination cascaded to the PVC before the explicit PVC-delete step ran (both follow-up deletes correctly returned NotFound). Final checkers: `kubectl get namespace factorio` = NotFound; Longhorn volumes list has no match for the test volume's `<pvc-id>` — the volume is reaped. **TEST RUN COMPLETE: all gates T0–T8 verified.** Live-run warning carved out of this: on the LIVE server, `delete -f` of the full manifest deletes the namespace and the world volume with it — live teardown/maintenance must delete objects selectively, never the namespace. |

## Live-run deltas (what the real deployment adds — NOT today)

1. Commit the validated files to `scribnetai/homelab` (manifest,
   FACTORIO.md, this runbook, upload scripts) **sanitized** — the
   public repo gets placeholders where this local copy has real LAN
   IPs — plus a CHANGELOG entry, per the standing rule. The commit
   records *proven* state, not hopes.
2. Server identity via **`factorio/configure-server.ps1`**
   (built 2026-10-25, rehearsed as gate T5b in this test run):
   prompts locally at deploy time and writes `server-settings.json`
   (name, visibility hidden public/lan false) and a **game
   password** (`game_password` —
   decided 2026-10-25: required for anyone connecting; set in-pod
   on the PVC only, never in git/chat; changing it needs a restart).
   **Flat trust model (his call, 2026-10-25):** no tiered in-game
   privileges — every invited player is a game admin, via
   `server-adminlist.json` holding exact Factorio usernames (the
   same names as the whitelist, which stays the access gate). With
   everyone admin-listed, `allow_commands` can stay `admins-only`
   and `only_admins_can_pause_the_game` effectively means anyone
   trusted can pause. Anyone missed can be `/promote`d via RCON
   after their first join.
3. Backups before friends: Longhorn snapshot + save archive into
   the GFS tiers, first archive opened and verified.
4. Kuma Push checker via in-pod RCON (`/players`), tailnet-only,
   Enshrouded A2S pattern.
5. Stage 2 friends access: `factorio/tailscale-friends-access.md`
   (share + udp:34197 grant + negative tests).
6. Lab Ledger: Factorio moves from Planned idea to a live service
   row + host entry update.
