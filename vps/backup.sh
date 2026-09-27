#!/usr/bin/env bash
# Back up the Uptime Kuma data volume to a timestamped tarball in ./backups/.
# Run on the VPS, then copy the tarball somewhere safe (your PC, etc.).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
STAMP="$(date +%Y%m%d-%H%M%S)"
docker run --rm \
  -v kuma-data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine:3 tar czf "/backup/kuma-data-${STAMP}.tgz" -C /data .
echo "OK: backups/kuma-data-${STAMP}.tgz"
echo "Copy it off the server, e.g.:"
echo "  scp techops@<vps-ip>:homelab/vps/backups/kuma-data-${STAMP}.tgz ."
