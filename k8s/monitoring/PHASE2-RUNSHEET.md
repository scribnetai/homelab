# Phase 2 run sheet — kube-prometheus-stack (Tue Oct 27, 18:15 ET)

Prepared Sun Oct 25, 2026, so Tuesday evening is an install session, not a
drafting session. Everything here is DRAFT / local — nothing installed,
nothing pushed. The plan itself was decided Sat Oct 24 and is recorded in
the `headlamp-phase2-prometheus-grafana` reminder; this sheet only turns
that plan into files + checkers.

Background in one paragraph: Phase 1A (Headlamp 0.46.0, hardened,
port-forward access) is live. The Tailscale operator was installed Sat
Oct 24 during PocketBase Step 6 and its Ingress pattern is proven
(hostname = first label of `spec.tls[0].hosts[0]`). Phase 2 adds
Prometheus + Grafana in ns `monitoring`; Grafana becomes the only new
tailnet door; Prometheus/Alertmanager are never exposed.

## Step 0 — daytime preflight (Mon or Tue, ~10 min, do this before 18:15)

```powershell
helm version
kubectl get nodes -o wide
kubectl get pvc -A
helm search repo prometheus-community/kube-prometheus-stack
```

Expect: both nodes `Ready` at 4 vCPU / 8 GB (the resized size, not the
stale 2/4 in old Terraform); the chart version printed by `helm search`
matches what gets pinned in Step 3 — ArtifactHub showed **92.11.0** on
Oct 25, but treat that as a lead, not a fact: pin whatever `helm search`
actually returns Tuesday and record it in the CHANGELOG.

Capacity gate (the one real unknown): the new PVCs are 10 Gi (Prometheus)
+ 5 Gi (Grafana) on `longhorn-rep2` = **30 Gi of raw disk per node** after
replication, on 80 GB node disks that already carry PocketBase's 10 Gi
(×2). Checker: `kubectl get pvc -A` totals + Longhorn UI free space. If a
node is tight, shrink Prometheus to 5 Gi in values.yaml *before* install —
do not discover it as a Pending PVC at 19:00.

## Step 1 — namespace + Grafana admin Secret (interactive, ~2 min)

Password comes from Dashlane at the keyboard; it never lands in a file,
a manifest, or git.

```powershell
kubectl create namespace monitoring
kubectl create secret generic grafana-admin -n monitoring --from-literal=admin-user=admin --from-literal=admin-password='<typed at the keyboard, never pasted into chat or a file>'
```

Checker: `kubectl get secret grafana-admin -n monitoring` → expect the
name listed, `DATA 2`. (Do not print the secret's contents as a check.)

## Step 2 — dry-run before anything real

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm template monitoring prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml | Select-String -Pattern "kind: (Prometheus|Grafana|StatefulSet|Deployment)" | Select-Object -First 20
```

Expect: a Prometheus CR, the operator + Grafana deployments, node-exporter
DaemonSet, kube-state-metrics — and **no Alertmanager anything** (disabled
in values on purpose; Kuma/Beszel own alerting).

## Step 3 — install

```powershell
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml --version <pinned in Step 0> --wait --timeout 10m
```

The 10-minute timeout is deliberate: Longhorn provisions on first consumer
and the images are cold pulls; Helm's 5-minute default is marginal here.

## Step 4 — verify in-cluster before any exposure

```powershell
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
kubectl get svc -n monitoring
```

Expect: all pods `Running`; both PVCs `Bound` on `longhorn-rep2`; note the
exact Grafana Service name — it must match `grafana-tailscale-ingress.yaml`
(`monitoring-grafana` if the release name above is used); fix the draft if
it differs, don't force it.

Prometheus sanity via localhost only (it is never exposed):

```powershell
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# browser: http://localhost:9090/targets
```

Expect: node-exporter, kube-state-metrics, apiserver, prometheus itself
UP. The control-plane targets (etcd / controller / scheduler / kube-proxy)
are *absent by design* — values.yaml disables them because k3s binds those
components to localhost; leaving them on would mean four permanently-Down
targets polluting every future dashboard.

## Step 5 — Grafana's tailnet door (the only one)

```powershell
kubectl apply -f grafana-tailscale-ingress.yaml
kubectl get ingress -n monitoring
```

Verify like PocketBase Step 6: `https://grafana.<tailnet>.ts.net` loads
from a tailnet device with a valid cert and Grafana's own login (anonymous
auth is OFF in values); then the off-tailnet proof — public DNS returns
the name with **no address records** (NODATA):

```powershell
nslookup grafana.<tailnet>.ts.net 8.8.8.8
```

Expect: name resolves in the tailnet tree but no A record — nothing for
the outside world to connect to. No Funnel, at any point, for any reason.

Optional ride-along (his call at session start, not a prerequisite):
apply Headlamp's already-committed `ingress.yaml` the same way.

## Step 6 — capture, same pass (standing rules)

- Push sanitized `values.yaml`, `grafana-tailscale-ingress.yaml` and this
  run sheet's outcome to `scribnetai/homelab` under `k8s/monitoring/`,
  with the chart version pinned in the commit and a CHANGELOG entry in
  the same pass (failure-driven or not — fleet rule).
- Update the Lab Ledger overlay (new service: Grafana; port-map/Key
  Commands note if the port convention grows) and rebuild xlsx + board.
- Add Headlamp's Prometheus plugin/view after Grafana is live (recorded
  Phase 2 follow-on, not a blocker).

## Hard stops / rollback

- PVC stuck `Pending` >5 min → stop, read Longhorn first
  (`kubectl get volumes -n longhorn-system`); do not delete and retry blind.
- Grafana login loop or secret mismatch → the Secret is the suspect;
  recreate it (Step 1) and `helm upgrade` — never put the password in
  values.yaml to "just make it work".
- Rollback is clean and boring: `helm uninstall monitoring -n monitoring`
  (PVCs survive an uninstall by default — decide explicitly whether to
  keep the 7 days of metrics before deleting them).

## Outcome — installed Sun Oct 25, 2026 (pulled forward from Tue Oct 27)

- **Step 0:** helm 4.3.1; chart pinned at **92.13.1** (what `helm search`
  returned that day — the 92.11.0 lead had already moved on). Capacity
  gate passed at full size (the only other PVC in the cluster was
  PocketBase's 10 Gi).
- **Step 1:** namespace + `grafana-admin` Secret created. One hiccup,
  caught by the checker pattern: the first attempt ran in a **cmd.exe**
  tab (Tabby's default local profile was cmd), so the Secret briefly
  held the literal text of the variable name instead of the password —
  the create had "succeeded," which is exactly why contents get verified
  (by decoded LENGTH, never by printing the value). Deleted, recreated
  in PowerShell, length-verified. Tabby's default profile is now
  PowerShell.
- **Steps 2–3:** template dry-run clean (no Alertmanager object; both
  storage classes `longhorn-rep2`); `helm install` → STATUS: deployed,
  revision 1.
- **Steps 4–5:** Grafana login proven via localhost port-forward
  (3000) with the Secret's password; then the Tailscale Ingress was
  applied — `https://grafana.<tailnet>.ts.net` loads on-tailnet with
  Grafana's own login, and public resolvers return no usable address
  records (verified off-tailnet). Prometheus stays ClusterIP-only;
  Alertmanager was never installed.
- **Capture:** this kit + `EXPOSURE.md` (Grafana → APPROVED — LIVE) +
  CHANGELOG in one commit; Lab Ledger updated (services rows + Key
  Commands row 17); the Tue Oct 27 reminder retired.
