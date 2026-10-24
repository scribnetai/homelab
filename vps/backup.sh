#!/usr/bin/env bash
# Back up the Uptime Kuma and Beszel data volumes to timestamped tarballs
# in ./backups/. Run on the VPS, then copy the tarballs somewhere safe
# (your PC, etc.). Beszel history is backed up on purpose (2026-10-24):
# the metrics history is the point of the hub, so it is worth keeping.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
STAMP="$(date +%Y%m%d-%H%M%S)"
docker run --rm \
  -v kuma-data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine:3 tar czf "/backup/kuma-data-${STAMP}.tgz" -C /data .
docker run --rm \
  -v beszel-data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine:3 tar czf "/backup/beszel-data-${STAMP}.tgz" -C /data .
echo "OK: backups/kuma-data-${STAMP}.tgz"
echo "OK: backups/beszel-data-${STAMP}.tgz"
echo "Copy them off the server, e.g.:"
echo "  scp labuser@<vps-ip>:homelab/vps/backups/*-${STAMP}.tgz ."
