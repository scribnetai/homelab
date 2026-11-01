#!/bin/bash
# renew-pbs-cert.sh — renew the Proxmox Backup Server web UI certificate.
#
# PBS serves its UI from a split pair: the chain in
# /etc/proxmox-backup/proxy.pem and the key in /etc/proxmox-backup/proxy.key
# (both root:backup, mode 640). The cert is a Let's Encrypt cert issued by
# `tailscale cert` for this node's own tailnet (MagicDNS) name — the name is
# read back from tailscaled at runtime, so nothing host-specific is baked in.
#
# Hash-gated like the Proxmox hosts' renewal script: the proxy restarts only
# when the issued cert actually changed, so the monthly run is a no-op until
# renewal is due.
#
# Install: /usr/local/bin/renew-pbs-cert.sh (root, mode 755)
# Cron:    20 3 1 * * /usr/local/bin/renew-pbs-cert.sh >/dev/null 2>&1
set -euo pipefail

PEM=/etc/proxmox-backup/proxy.pem
PKEY=/etc/proxmox-backup/proxy.key
WORK=/root

HOST="$(tailscale status --json | grep -o '"DNSName": "[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')"
[ -n "$HOST" ] || { echo "could not determine tailnet DNS name" >&2; exit 1; }

cd "$WORK"
tailscale cert "$HOST"
CRT="$WORK/$HOST.crt"
KEY="$WORK/$HOST.key"

if cmp -s "$CRT" "$PEM" && cmp -s "$KEY" "$PKEY"; then
    exit 0
fi

install -o root -g backup -m 640 "$CRT" "$PEM"
install -o root -g backup -m 640 "$KEY" "$PKEY"
systemctl restart proxmox-backup-proxy
