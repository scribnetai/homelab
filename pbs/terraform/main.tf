# Proxmox Backup Server VM, managed by Terraform.
#
# ONE VM on NUC-1, installed from the official PBS ISO (interactive
# installer -- there is no cloud-init path for PBS). Terraform creates the
# VM with the ISO attached and starts it; a human runs the installer in the
# console, then the cdrom block comes out in a follow-up change.
#
# The datastore is NOT a virtual disk: the host's USB backup drive is
# passed through whole to this VM after the install (qm set, by hand --
# the provider has no first-class USB passthrough block) and formatted
# inside PBS. The datastore directory is self-describing, so the drive
# can be attached to any fresh PBS/PVE install and every backup restored
# from it, even if the whole cluster is gone. VM configs ride inside the
# backup snapshots themselves.
#
# Auth via env var: PROXMOX_VE_API_TOKEN (same token as the k3s module).
# Never commit the token. Real endpoint/IP values live only in the local
# terraform.tfvars (gitignored); this file carries doc-range defaults.

locals {
  # x86-64-v2-AES = the fleet common denominator (D7): this VM must be
  # restorable/migratable onto any modern host, never pinned to one CPU.
  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 4096
  disk_gb  = 32
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure_tls
  # Auth via env var: PROXMOX_VE_API_TOKEN=<redacted>
  # (Datacenter -> Permissions -> API Tokens). Never commit the token.
}

resource "proxmox_virtual_environment_vm" "pbs" {
  name        = "pbs"
  description = "Proxmox Backup Server -- fleet backups; datastore on the passed-through USB drive. Managed by Terraform."
  node_name   = var.pbs_node
  vm_id       = var.pbs_vm_id

  cpu {
    cores = local.cores
    type  = local.cpu_type
  }

  memory {
    dedicated = local.memory
  }

  # Boot disk only. The datastore drive arrives by USB passthrough after
  # the OS install -- deliberately not a virtual disk (portability).
  disk {
    datastore_id = var.vm_datastore
    interface    = "virtio0"
    size         = local.disk_gb
  }

  cdrom {
    file_id   = var.pbs_iso
    interface = "ide2"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # The PBS installer image ships no qemu-guest-agent; enabling the agent
  # here would stall applies waiting for a ping that never comes.
  agent {
    enabled = false
  }

  on_boot = true
  started = true
}
