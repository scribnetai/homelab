#!/usr/bin/env bash
#
# k3s cluster bootstrap for the homelab.
#
# Run on the Proxmox VM that will be the control plane first, then on each
# worker with the token the server prints.
#
#   Server:  sudo bash k3s-install.sh server
#   Agent:   sudo K3S_URL=https://<server-tailscale-ip>:6443 K3S_TOKEN=<token> bash k3s-install.sh agent
#
# Nodes join over Tailscale IPs (not lab-net IPs) so the exact same commands
# work later if the VPS joins as a hybrid agent. The server's Tailscale IP is
# added as a TLS SAN so your PC's kubeconfig works remotely.
#
# Optional: K3S_VERSION=v1.34.2+k3s1  (empty = k3s stable channel)
#
set -euo pipefail

ROLE="${1:-}"
: "${K3S_VERSION:=}"

if [[ "$ROLE" == "server" ]]; then
    NODE_IP="$(tailscale ip -4 2>/dev/null || hostname -I | awk '{print $1}')"
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - server \
        --cluster-init \
        --tls-san "$NODE_IP" \
        --write-kubeconfig-mode 644
    echo
    echo "--- Server is up. Agent join token (also at /var/lib/rancher/k3s/server/node-token):"
    cat /var/lib/rancher/k3s/server/node-token
    echo
    echo "--- Next steps:"
    echo "1. sudo K3S_URL=https://$NODE_IP:6443 K3S_TOKEN=<token above> bash k3s-install.sh agent   (on each worker)"
    echo "2. Copy /etc/rancher/k3s/k3s.yaml to your PC as ~/.kube/homelab.yaml,"
    echo "   replace 127.0.0.1 with $NODE_IP, and point KUBECONFIG at it."
    echo "3. kubectl get nodes"

elif [[ "$ROLE" == "agent" ]]; then
    : "${K3S_URL:?Set K3S_URL to https://<server-tailscale-ip>:6443}"
    : "${K3S_TOKEN:?Set K3S_TOKEN to the join token printed by the server install}"
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent
    echo "--- Agent joined. Verify from your PC: kubectl get nodes"

else
    echo "Usage: $0 server|agent" >&2
    exit 1
fi
