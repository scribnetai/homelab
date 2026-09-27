#!/usr/bin/env bash
# Restore a kuma-data tarball (made by backup.sh) into the named volume.
# Usage (from the vps/ directory, tarball path relative to vps/):
#   ./restore.sh backups/kuma-data-20260927-120000.tgz
set -euo pipefail
cd "$(dirname "$0")"
TARBALL="${1:?usage: ./restore.sh <path-to-tarball, relative to vps/>}"
[ -f "$TARBALL" ] || { echo "not found: $TARBALL"; exit 1; }
case "$TARBALL" in /*) echo "use a path relative to vps/, not absolute"; exit 1;; esac
docker compose stop uptime-kuma 2>/dev/null || true
docker run --rm \
  -v kuma-data:/data \
  -v "$PWD:/work" \
  alpine:3 sh -c "rm -rf /data/* && tar xzf \"/work/${TARBALL}\" -C /data"
docker compose up -d uptime-kuma
echo "OK: restored ${TARBALL} into volume kuma-data"
