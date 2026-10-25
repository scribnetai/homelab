#!/usr/bin/env bash
# configure-server.sh — bash twin of configure-server.ps1.
# Set the Factorio game password and the admin/whitelist name lists
# on the k3s server's PVC, interactively. See configure-server.ps1
# for the full security model; in short: the password is typed at a
# hidden prompt, lives only in a local 0700 temp dir during the run
# (deleted on exit), and is never an argument, env var, manifest
# value, or chat/git content. Verification prints its LENGTH only.
#
#   ./configure-server.sh                  # password + admins (+ whitelist)
#   ./configure-server.sh --skip-whitelist
#
# Requires: kubectl, python3 (local JSON edit only).
set -euo pipefail

NAMESPACE="factorio"
STATEFULSET="factorio"
CLAIM="factorio-data-factorio-0"
HELPER="factorio-config"
SKIP_WHITELIST=0
[ "${1:-}" = "--skip-whitelist" ] && SKIP_WHITELIST=1

command -v python3 >/dev/null || { echo "python3 is required for the local JSON edit." >&2; exit 1; }

# --- 1. Password prompt (before any downtime) ------------------------
read -rsp "Game password for the server (input hidden): " PW1; echo
read -rsp "Repeat the game password: " PW2; echo
[ -n "$PW1" ] || { echo "Password must not be empty." >&2; exit 1; }
[ "$PW1" = "$PW2" ] || { echo "Passwords did not match — nothing was changed." >&2; exit 1; }
PW2=""
echo "Password captured (length ${#PW1}). It will not be printed."

# --- 2. Preflight ------------------------------------------------------
kubectl cluster-info >/dev/null
kubectl -n "$NAMESPACE" get statefulset "$STATEFULSET" >/dev/null

TMP="$(mktemp -d)"
chmod 700 "$TMP"
SCALED_DOWN=0
cleanup() {
  rm -rf "$TMP"
  if [ "$SCALED_DOWN" = "1" ]; then
    echo "WARNING: server is still scaled to 0 and helper pod '$HELPER' may still be running." >&2
    echo "To abandon and restart as-was: kubectl -n $NAMESPACE delete pod $HELPER; kubectl -n $NAMESPACE scale statefulset/$STATEFULSET --replicas=1" >&2
    echo "(Pre-change settings are on the PVC as server-settings.json.bak.)" >&2
  fi
}
trap cleanup EXIT

# --- 3. Scale down, helper pod ----------------------------------------
echo "Scaling $STATEFULSET to 0..."
kubectl -n "$NAMESPACE" scale statefulset "$STATEFULSET" --replicas=0
SCALED_DOWN=1
kubectl -n "$NAMESPACE" wait --for=delete "pod/$STATEFULSET-0" --timeout=120s 2>/dev/null || true

OVERRIDES=$(cat <<JSON
{"spec":{"nodeSelector":{"example.com/game-server":"true"},"restartPolicy":"Never","containers":[{"name":"factorio-config","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"$CLAIM"}}]}}
JSON
)
kubectl -n "$NAMESPACE" delete pod "$HELPER" --ignore-not-found >/dev/null 2>&1 || true
echo "Starting helper pod ($HELPER)..."
kubectl -n "$NAMESPACE" run "$HELPER" --image=busybox:1.36 --restart=Never --overrides "$OVERRIDES" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$HELPER" --timeout=120s >/dev/null
kubectl -n "$NAMESPACE" exec "$HELPER" -- mkdir -p /data/config

# --- 4. Backup + copy settings out -------------------------------------
kubectl -n "$NAMESPACE" exec "$HELPER" -- cp /data/config/server-settings.json /data/config/server-settings.json.bak 2>/dev/null || true
kubectl -n "$NAMESPACE" cp "$HELPER:/data/config/server-settings.json" "$TMP/server-settings.json"
kubectl -n "$NAMESPACE" cp "$HELPER:/data/config/server-adminlist.json" "$TMP/server-adminlist.json" 2>/dev/null || true

EXISTING=""
if [ -s "$TMP/server-adminlist.json" ]; then
  EXISTING=$(python3 -c "import json,sys; print(','.join(json.load(open(sys.argv[1]))))" "$TMP/server-adminlist.json" 2>/dev/null || true)
fi

# --- 5. Admins: keep existing or replace --------------------------------
if [ -n "$EXISTING" ]; then
  echo "Current admin list: $EXISTING"
  read -rp "Admin Factorio usernames, comma-separated (Enter = keep current list): " TYPED
else
  read -rp "Admin Factorio usernames, comma-separated (include YOURSELF): " TYPED
fi
ADMINS_CSV="${TYPED:-$EXISTING}"
[ -n "$ADMINS_CSV" ] || { echo "Admin list is empty — refusing to continue." >&2; exit 1; }

# --- 6. Local edit: password + identity into settings, lists as JSON ---
# Server name + description (mirror of the .ps1): prompt with the
# current values as defaults; Enter keeps. First boot ships
# placeholder text here ("Name of the game as it will appear ...").
CUR_NAME=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('name',''))" "$TMP/server-settings.json")
CUR_DESC=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('description',''))" "$TMP/server-settings.json")
read -rp "Server name [current: $CUR_NAME] (Enter keeps): " TYPED_NAME
[ -n "$TYPED_NAME" ] && CUR_NAME="$TYPED_NAME"
read -rp "Server description [current: $CUR_DESC] (Enter keeps): " TYPED_DESC
[ -n "$TYPED_DESC" ] && CUR_DESC="$TYPED_DESC"
export FACTORIO_NAME="$CUR_NAME" FACTORIO_DESC="$CUR_DESC"
echo "Server identity: '$CUR_NAME' -- '$CUR_DESC'"
printf '%s' "$PW1" > "$TMP/pw.txt"; chmod 600 "$TMP/pw.txt"
python3 - "$TMP/server-settings.json" "$TMP/pw.txt" "$ADMINS_CSV" "$TMP/server-adminlist.json" "$TMP/server-whitelist.json" <<'PY'
import json, os, sys
settings_path, pw_path, admins_csv, admins_path, whitelist_path = sys.argv[1:6]
with open(pw_path) as f:
    pw = f.read()
with open(settings_path) as f:
    settings = json.load(f)
settings["game_password"] = pw
settings["name"] = os.environ.get("FACTORIO_NAME", settings.get("name", ""))
settings["description"] = os.environ.get("FACTORIO_DESC", settings.get("description", ""))
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
admins = sorted({a.strip() for a in admins_csv.split(",") if a.strip()})
if not admins:
    sys.exit("Admin list is empty after parsing.")
for path in (admins_path, whitelist_path):
    with open(path, "w") as f:
        json.dump(admins, f)
print("Admins (= whitelist unless --skip-whitelist): " + ", ".join(admins))
PY

# --- 7. Copy back ---------------------------------------------------------
kubectl -n "$NAMESPACE" cp "$TMP/server-settings.json" "$HELPER:/data/config/server-settings.json"
kubectl -n "$NAMESPACE" cp "$TMP/server-adminlist.json" "$HELPER:/data/config/server-adminlist.json"
if [ "$SKIP_WHITELIST" = "0" ]; then
  kubectl -n "$NAMESPACE" cp "$TMP/server-whitelist.json" "$HELPER:/data/config/server-whitelist.json"
fi

# --- 8. Verify WITHOUT printing the password ------------------------------
echo "Checker: server name line on the PVC = $(kubectl -n "$NAMESPACE" exec "$HELPER" -- grep -m1 '"name"' /data/config/server-settings.json)"
PWLEN=$(kubectl -n "$NAMESPACE" exec "$HELPER" -- awk -F'"' '/"game_password"/ {print length($4); exit}' /data/config/server-settings.json)
echo "Checker: game_password length on the PVC = $PWLEN (expected ${#PW1})"
[ "$PWLEN" = "${#PW1}" ] || { echo "Password length mismatch — do NOT start the server until reconciled." >&2; exit 1; }
echo "Checker: server-adminlist.json on the PVC = $(kubectl -n "$NAMESPACE" exec "$HELPER" -- cat /data/config/server-adminlist.json)"
if [ "$SKIP_WHITELIST" = "0" ]; then
  echo "Checker: server-whitelist.json on the PVC = $(kubectl -n "$NAMESPACE" exec "$HELPER" -- cat /data/config/server-whitelist.json)"
fi

# --- 9. Helper out, server up ----------------------------------------------
kubectl -n "$NAMESPACE" delete pod "$HELPER" --wait=true >/dev/null
echo "Scaling $STATEFULSET back to 1..."
kubectl -n "$NAMESPACE" scale statefulset "$STATEFULSET" --replicas=1
SCALED_DOWN=0
kubectl -n "$NAMESPACE" rollout status "statefulset/$STATEFULSET" --timeout=180s

echo ""
echo "Done. Prove it with a real join: expect a PASSWORD PROMPT before joining,"
echo "and your name should carry admin. Wrong/no password must fail."
