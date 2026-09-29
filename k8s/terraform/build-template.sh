#!/usr/bin/env bash
#
# Build of the Ubuntu 24.04 cloud-init template used by k8s/terraform.
#
# Run on EACH Proxmox node that will host k3s VMs (it calls qm directly).
# Standalone nodes: run on both (each node clones from its own local copy).
# Clustered nodes: once is enough (VMIDs are cluster-wide). E.g.:
#   scp build-template.sh root@<proxmox-node>:/tmp/
#   ssh root@<proxmox-node> "bash /tmp/build-template.sh"
#
# Override the template ID with: TEMPLATE_ID=9001 bash build-template.sh
#
set -euo pipefail

TEMPLATE_ID="${TEMPLATE_ID:-9000}"
IMG="noble-server-cloudimg-amd64.img"
URL="https://cloud-images.ubuntu.com/noble/current/${IMG}"

cd /tmp
if [[ ! -f "$IMG" ]]; then
  echo "Downloading Ubuntu 24.04 cloud image..."
  curl -fSLO "$URL"
fi

# Start clean if a previous template with this ID exists.
qm destroy "$TEMPLATE_ID" --purge 2>/dev/null || true

qm create "$TEMPLATE_ID" \
  --name ubuntu-2404-cloud \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0

qm importdisk "$TEMPLATE_ID" "$IMG" local-lvm
qm set "$TEMPLATE_ID" --scsihw virtio-scsi-pci --scsi0 "local-lvm:vm-${TEMPLATE_ID}-disk-0"
qm set "$TEMPLATE_ID" --ide2 local:cloudinit --boot c --bootdisk scsi0
qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
qm set "$TEMPLATE_ID" --agent enabled=1
qm template "$TEMPLATE_ID"

echo "Template ${TEMPLATE_ID} (ubuntu-2404-cloud) ready."
