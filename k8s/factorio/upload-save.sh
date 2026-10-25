#!/usr/bin/env bash
# upload-save.sh — Bash twin of upload-save.ps1 (same flow, same
# safety stops). See ../FACTORIO.md.
#   ./upload-save.sh --save ~/saves/scribnet-space-age.zip [--clean-throwaway] [--mods ~/mods]
set -euo pipefail

SAVE="" MODS="" CLEAN=0
NS="factorio" STS="factorio" CLAIM="factorio-data-factorio-0" HELPER="factorio-upload"
while [ $# -gt 0 ]; do
  case "$1" in
    --save) SAVE="$2"; shift 2;;
    --mods) MODS="$2"; shift 2;;
    --clean-throwaway) CLEAN=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$SAVE" ] || { echo "usage: $0 --save <save.zip> [--mods <dir>] [--clean-throwaway]" >&2; exit 2; }
[ -f "$SAVE" ] || { echo "save not found: $SAVE" >&2; exit 1; }
case "$SAVE" in *.zip) ;; *) echo "Factorio saves are .zip files: $SAVE" >&2; exit 1;; esac

# 1. Validate the save locally (a Factorio save zip contains level.dat)
if command -v unzip >/dev/null 2>&1; then
  unzip -l "$SAVE" | grep -q 'level\.dat' || { echo "$SAVE contains no level.dat — not a Factorio save zip." >&2; exit 1; }
else
  python3 -c 'import sys,zipfile; sys.exit(0 if any("level.dat" in n for n in zipfile.ZipFile(sys.argv[1]).namelist()) else 1)' "$SAVE" \
    || { echo "$SAVE contains no level.dat — not a Factorio save zip." >&2; exit 1; }
fi
SAVE_NAME="$(basename "$SAVE")"
echo "Save validated: $SAVE_NAME"

# 2. Preflight
kubectl cluster-info >/dev/null
kubectl -n "$NS" get statefulset "$STS" >/dev/null

# 3. Stop the server
echo "Scaling $STS to 0..."
kubectl -n "$NS" scale statefulset "$STS" --replicas=0
kubectl -n "$NS" wait --for=delete "pod/$STS-0" --timeout=120s 2>/dev/null || true

# 4. Helper pod, same node, same PVC
kubectl -n "$NS" delete pod "$HELPER" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NS" run "$HELPER" --image=busybox:1.36 --restart=Never --overrides='{
  "spec": {
    "nodeSelector": {"example.com/game-server": "true"},
    "restartPolicy": "Never",
    "containers": [{
      "name": "factorio-upload", "image": "busybox:1.36",
      "command": ["sleep", "3600"],
      "volumeMounts": [{"name": "data", "mountPath": "/data"}]
    }],
    "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "'"$CLAIM"'"}}]
  }
}'
kubectl -n "$NS" wait --for=condition=Ready "pod/$HELPER" --timeout=120s
kubectl -n "$NS" exec "$HELPER" -- mkdir -p /data/saves /data/mods

# 5. Back up the current saves (before anything is deleted).
# Same rule as upload-save.ps1: every .zip in /data/saves is copied
# to /data/backups/upload-<timestamp>/ on the same PVC (a pre-change
# safety net, not the off-box backup layer). Skips cleanly if empty.
mapfile -t CURRENT_ZIPS < <(kubectl -n "$NS" exec "$HELPER" -- sh -c "ls -1 /data/saves/*.zip 2>/dev/null" || true)
if [ "${#CURRENT_ZIPS[@]}" -gt 0 ] && [ -n "${CURRENT_ZIPS[0]}" ]; then
  BACKUP_DIR="/data/backups/upload-$(date +%Y%m%d-%H%M%S)"
  echo "Backing up ${#CURRENT_ZIPS[@]} existing save(s) to $BACKUP_DIR ..."
  kubectl -n "$NS" exec "$HELPER" -- mkdir -p "$BACKUP_DIR"
  for z in "${CURRENT_ZIPS[@]}"; do
    kubectl -n "$NS" exec "$HELPER" -- cp -a "$z" "$BACKUP_DIR/"
  done
  BACKED_UP=$(kubectl -n "$NS" exec "$HELPER" -- sh -c "ls -1 $BACKUP_DIR | wc -l")
  echo "Backup contents:"
  kubectl -n "$NS" exec "$HELPER" -- ls -1 "$BACKUP_DIR" | sed 's/^/  /'
  [ "$BACKED_UP" = "${#CURRENT_ZIPS[@]}" ] || { echo "Backup verification failed: $BACKED_UP of ${#CURRENT_ZIPS[@]} saves copied. Server left at 0; helper left running." >&2; exit 1; }
else
  echo "No existing saves in the PVC -- nothing to back up."
fi

# 6. Optional throwaway cleanup
if [ "$CLEAN" = "1" ]; then
  mapfile -t THROWAWAY < <(kubectl -n "$NS" exec "$HELPER" -- ls -1 /data/saves | grep -E '^_autosave.*\.zip$' | grep -v -x "$SAVE_NAME" || true)
  if [ "${#THROWAWAY[@]}" -gt 0 ]; then
    printf 'Throwaway saves that will be deleted:\n'; printf '  %s\n' "${THROWAWAY[@]}"
    read -r -p "Type yes to delete: " ANSWER
    [ "$ANSWER" = "yes" ] || { echo "Aborted. Server still at 0; helper left running." >&2; exit 1; }
    for f in "${THROWAWAY[@]}"; do kubectl -n "$NS" exec "$HELPER" -- rm -f "/data/saves/$f"; done
  else
    echo "No throwaway _autosave zips found."
  fi
fi

# 6. Copy in
echo "Uploading $SAVE_NAME ..."
kubectl -n "$NS" cp "$SAVE" "$NS/$HELPER:/data/saves/$SAVE_NAME"
if [ -n "$MODS" ]; then
  for m in "$MODS"/*.zip; do
    [ -e "$m" ] || continue
    echo "Uploading mod $(basename "$m") ..."
    kubectl -n "$NS" cp "$m" "$NS/$HELPER:/data/mods/$(basename "$m")"
  done
fi

# 7. Verify newest
LISTING="$(kubectl -n "$NS" exec "$HELPER" -- sh -c 'ls -t /data/saves/*.zip')"
[ -n "$LISTING" ] || { echo "Could not list saves in PVC. Server left at 0; helper left running." >&2; exit 1; }
NEWEST="$(basename "$(printf '%s\n' "$LISTING" | head -1)")"
printf 'Saves in PVC, newest first:\n%s\n' "$LISTING"
[ "$NEWEST" = "$SAVE_NAME" ] || { echo "Newest save is '$NEWEST', not '$SAVE_NAME'. Server left at 0 on purpose." >&2; exit 1; }

# 8. Cleanup + start
kubectl -n "$NS" delete pod "$HELPER" --wait=true
kubectl -n "$NS" scale statefulset "$STS" --replicas=1
kubectl -n "$NS" rollout status "statefulset/$STS" --timeout=180s
echo
echo "Done. Prove it: kubectl -n $NS logs statefulset/$STS -f   (expect your save loading)"
echo "LAN join (first pass): Multiplayer > Connect to address > <agent-lan-ip>:34197"
