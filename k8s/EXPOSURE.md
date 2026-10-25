# Exposure gate — tailnet doors for cluster UIs

The Tailscale Kubernetes operator is the cluster's shared front door:
install once, reuse per app. That convenience is exactly why doors get a
gate. **No Tailscale Ingress is applied for a cluster service unless its
row in the matrix below is complete and its decision is APPROVED.**
Applying a door is always a separate, explicit decision — this file is
documentation and policy only; it never changes an Ingress, ACL, or
Service by itself.

Decided 2026-10-24, after the PocketBase front door (Step 6) made the
pattern real: the same operator fronts PocketBase today, Headlamp next,
and Grafana in Phase 2 — the auth call gets made once per app, here,
instead of being re-decided under time pressure at each deploy.

## Gate checklist (every box, before a door goes live)

- [ ] The app has its **own authentication**, or a compensating control
      is written into its row and explicitly approved. Default for a
      no-auth app is **no door**.
- [ ] The default identity's privileges are written down and are
      least-privilege: no standing cluster-admin, no unexamined
      chart-default bindings, short-lived tokens where supported.
- [ ] The Service stays **ClusterIP**. No NodePort, LoadBalancer, or LAN
      Ingress as a side door. **No Tailscale Funnel annotation, ever** —
      and the tailnet policy must grant no funnel attribute.
- [ ] Secrets live only in Kubernetes Secrets or the operator's vault —
      never in this repo. Tokens are minted (TokenRequest), not stored.
- [ ] The verification pack below passes, and the results are recorded
      in the CHANGELOG in the same pass as the manifest change.

## The matrix

| App (namespace) | Door | Own auth | Default identity & privileges | Decision / status |
|---|---|---|---|---|
| PocketBase (`finance`) | Tailscale Ingress → `https://pocketbase.<tailnet>.ts.net` | Superuser login for the `/_/` admin UI; collection rules govern the API. `/api/health` answers unauthenticated to tailnet callers — accepted and recorded here, not an oversight. | Superuser = full PocketBase admin (single operator; credential in the password vault). App access uses the low-privilege app user (Step 7), never the superuser. | **APPROVED — LIVE 2026-10-24.** Verified: HTTPS loads on-tailnet with a valid cert; public DNS returns no address records. |
| Headlamp (`headlamp`) | Ingress manifest staged (`headlamp/ingress.yaml`); **not applied** — port-forward (`localhost:8081`) only today | Bearer-token login. The pod's own service account has **no** privileges (`clusterRoleBinding.create: false`, `unsafeUseServiceAccountToken: false`), so every request runs as the logged-in identity. | `headlamp-viewer`: built-in `view` ClusterRole + a nodes/metrics extra role. No Secrets, no exec, no writes; 24h token. Admin is ad hoc at 1h — no standing admin identity. | **STAGED 2026-10-24.** Applying the Ingress is this gate's first live case: explicit decision + verification pack. |
| Longhorn UI (`longhorn-system`) | **No door.** Port-forward (`localhost:8080`) only | **None — the UI has no login at all** | Anyone who reaches the UI is effectively storage admin | **DENIED / PARKED** (operator's call, 2026-10-24). Revisit only as an explicit numbered decision, ideally with tailnet ACL scoping as the compensating control. |
| Grafana (`monitoring`, planned Phase 2) | Tailscale Ingress planned after kube-prometheus-stack lands | Own login; anonymous access **off**; admin password only in a Kubernetes Secret | Grafana admin via the Secret; additional users read-only | **ELIGIBLE, NOT YET APPROVED.** This row must be completed with live values and the decision recorded before the Ingress is applied. |
| Prometheus (`monitoring`, planned Phase 2) | **None — ClusterIP only, permanently** | None built in | n/a | **PERMANENTLY DENIED.** Query it through Grafana's datasource or a port-forward. |
| Alertmanager (`monitoring`, planned Phase 2) | **None — ClusterIP only, permanently** | None built in | n/a | **PERMANENTLY DENIED.** Silences/acks happen via port-forward or a future gated tool, never a door. |

## Verification pack (run for every door, and on any audit)

```
kubectl get ingress -A
# expect: only rows marked LIVE above — nothing else, ever

kubectl get ingress,svc -A -o yaml | grep -i funnel
# expect: nothing (Funnel would publish the service publicly)

nslookup <app>.<tailnet>.ts.net 8.8.8.8
# expect: no A/AAAA records returned (NODATA or NXDOMAIN) — the name
# must not resolve outside the tailnet

curl -s https://<app>.<tailnet>.ts.net/        # from on-tailnet, unauthenticated
# expect: a login/token gate — except PocketBase /api/health, which is
# recorded above as intentionally answering on-tailnet
```

If any check fails: **the door comes down first** (`kubectl delete
ingress <name> -n <ns>`), diagnosis second.

## How a new door gets approved

1. Complete its matrix row in the same commit as the Ingress manifest.
2. Record the decision and date (the operator's call, not the chart's
   default).
3. Apply, run the verification pack, record results in the CHANGELOG.
4. Any failed check → door down first, per above.

Scope: this gate covers Tailscale-operator Ingresses in the cluster.
Non-cluster doors (`tailscale serve` for the VPS monitoring stack) follow
the same principles and are documented under `vps/`.
