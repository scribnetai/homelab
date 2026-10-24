# Headlamp - in-cluster Kubernetes web UI

Headlamp (CNCF, by the Kubernetes SIG-UI) is the cluster's web UI: the
maintained successor to the archived Kubernetes Dashboard, and the
web-native answer to the unmaintained OpenLens desktop builds.
Deployed 2026-10-24 as Phase 1 of the cluster-observability track;
Phase 2 (Prometheus + Grafana via kube-prometheus-stack) is planned
separately under `k8s/monitoring/`.

## What runs

- Namespace `headlamp`, Helm release `headlamp`, chart/app 0.46.0.
- One pod, requests 50m CPU / 128Mi, limits 500m / 512Mi.
- Service type ClusterIP only - no LoadBalancer, no NodePort.

## Security model (the reason for the custom values)

- The upstream chart by default binds Headlamp's own service account
  to `cluster-admin`. `values.yaml` disables that binding
  (`clusterRoleBinding.create: false`) and pins
  `config.unsafeUseServiceAccountToken: false`, so the pod itself has
  no API privileges; every request runs as the logged-in user.
- `config.enableHelm: false` is pinned off (CVE-2025-14269: credential
  caching when Helm integration is enabled; fixed in 0.39.0, feature
  stays off anyway).
- Login = a short-lived ServiceAccount token minted with
  `kubectl create token` (TokenRequest API; nothing is stored in a
  Secret, and no token ever goes in this repo). Daily identity is
  `headlamp-viewer` (see `rbac.yaml`): read-only, no Secrets, no exec,
  no writes; 24h token lifetime. Admin access is minted ad hoc at 1h
  when actually needed - there is no standing admin identity.
- Network door (Phase 1B) is `ingress.yaml`: Tailscale operator,
  tailnet-only HTTPS. Tailscale Funnel is never used, and the tailnet
  policy is checked to grant no funnel attribute before deploys.
  Until the Ingress lands, access is by port-forward (below).

## Install / reinstall

```
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
helm install headlamp headlamp/headlamp \
  --namespace headlamp --create-namespace \
  -f values.yaml --wait
kubectl apply -f rbac.yaml
kubectl create token headlamp-viewer -n headlamp --duration=24h
kubectl port-forward -n headlamp svc/headlamp 8081:80
# browse http://localhost:8081 and paste the token
```

Local port convention on the operator workstation (port-forwards
only): 8080 = Longhorn UI, 8081 = Headlamp, 8090 = PocketBase admin.

## Verification pack (read-only)

```
kubectl get pods,svc -n headlamp
kubectl get clusterrolebindings | grep headlamp
kubectl auth can-i get pods -n finance \
  --as=system:serviceaccount:headlamp:headlamp-viewer   # expect: yes
kubectl auth can-i get secrets -n finance \
  --as=system:serviceaccount:headlamp:headlamp-viewer   # expect: no
kubectl auth can-i delete pods -n finance \
  --as=system:serviceaccount:headlamp:headlamp-viewer   # expect: no
kubectl auth can-i create pods/exec -n finance \
  --as=system:serviceaccount:headlamp:headlamp-viewer   # expect: no
kubectl get ingress,svc -A -o yaml | grep -i funnel      # expect: nothing
```

On deploy day the pod was Running with a ClusterIP-only Service,
and the overview rendered live metrics (nodes, CPU/memory gauges)
under the viewer identity - the functional proof that the viewer
binding plus the nodes/metrics role are sufficient and sufficient
only. Run the can-i lines above to re-prove the boundaries any time.

## Rollback

```
helm uninstall headlamp -n headlamp
kubectl delete -f rbac.yaml
kubectl delete namespace headlamp
```
