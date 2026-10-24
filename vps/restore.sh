#!/usr/bin/env bash
# Restore a data tarball (made by backup.sh) into its named volume.
# Usage (from the vps/ directory, tarball path relative to vps/):
#   ./restore.sh backups/kuma-data-20260927-120000.tgz
#   ./restore.sh backups/beszel-data-20261024-120000.tgz
# The volume and service are picked from the tarball name.
set -euo pipefail
cd "$(dirname "$0")"
TARBALL="${1:?usage: ./restore.sh <path-to-tarball, relative to vps/>}"
[ -f "$TARBALL" ] || { echo "not found: $TARBALL"; exit 1; }
case "$TARBALL" in /*) echo "use a path relative to vps/, not absolute"; exit 1;; esac
BASE="$(basename "$TARBALL")"
case "$BASE" in
  kuma-data-*.tgz)   VOL="kuma-data";   SVC="uptime-kuma" ;;
  beszel-data-*.tgz) VOL="beszel-data"; SVC="beszel" ;;
  *) echo "unrecognized tarball: $BASE (expected kuma-data-*.tgz or beszel-data-*.tgz)"; exit 1 ;;
esac
docker compose stop "$SVC" 2>/dev/null || true
docker run --rm \
  -v "$VOL":/data \
  -v "$PWD:/work" \
  alpine:3 sh -c "rm -rf /data/* && tar xzf \"/work/${TARBALL}\" -C /data"
docker compose up -d "$SVC"
echo "OK: restored ${TARBALL} into volume ${VOL}"
