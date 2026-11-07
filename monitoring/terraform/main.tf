# Monitoring VM, managed by Terraform.
#
# ONE VM on proxmox2, cloned from that node's Ubuntu 24.04 cloud
# template (the immich/pihole module pattern). The monitoring tools
# run inside the VM as Docker Compose stacks (../docker-compose.yml
# is the first tenant) -- the VM is the durable unit; the containers
# are replaceable payloads.
#
# Why a dedicated VM (decided 2026-11-06, owner's call): the first
# tenant is PeaNUT, the dashboard for the NUT server that landed the
# same day on proxmox2 (USB UPS monitoring). Hermes VM and k3s were
# both workable homes; a dedicated monitoring VM won because more
# monitoring tools are expected to join it, and a viewer of the
# fleet should not share fate with an agent host or the cluster it
# may need to watch fail.
#
# Why proxmox2: it holds the fleet's RAM headroom, and it is the NUT
# server's own host -- the watcher lives with the watched.
#
# Sizing is deliberately small (2 vCPU / 4 GB / 32 GB): dashboards
# and scrapers are light. Grow it in locals when a tenant earns it.
#
# CPU type is x86-64-v2-AES (fleet standard): the VM must be
# migratable/restorable onto ANY host, never pinned to one CPU.
#
# Cloud-init installs the qemu guest agent, Docker, and Tailscale.
# You run `tailscale up` once by hand afterwards -- no Tailscale
# auth keys are committed anywhere in this repo.
#
# Backup posture: the Proxmox Backup Server nightly job covers ALL
# VMs, so this disk lands on the PBS datastore every night like the
# rest of the fleet.
#
# Auth via env var: PROXMOX_VE_API_TOKEN (same token as the k3s and
# pbs modules), plus the provider's SSH leg (PROXMOX_VE_SSH_*) for
# the snippet upload -- plan never exercises the SSH leg, only apply
# does. Never commit the token. Real endpoint/IP values live only in
# the local terraform.tfvars (gitignored); this file carries
# doc-range defaults.

locals {
  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 4096
  disk_gb  = 32
  hostname = "monitoring"
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure_tls
  # Auth via env var: PROXMOX_VE_API_TOKEN (Datacenter -> Permissions
  # -> API Tokens). Never commit the token.
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.cloudinit_datastore
  node_name    = var.monitoring_node

  source_raw {
    file_name = "monitoring-user-data.yaml"
    data = templatefile("${path.module}/files/user-data.yaml.tftpl", {
      hostname = local.hostname
      username = var.ssh_username
      ssh_keys = var.ssh_public_keys
    })
  }
}

resource "proxmox_virtual_environment_vm" "monitoring" {
  name            = "monitoring"
  description     = "Monitoring tools home -- PeaNUT (NUT dashboard) first tenant, Docker Compose inside -- managed by Terraform (monitoring/terraform)"
  tags            = ["monitoring", "terraform"]
  node_name       = var.monitoring_node
  vm_id           = var.monitoring_vm_id
  stop_on_destroy = true

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = local.cores
    type  = local.cpu_type
  }

  memory {
    dedicated = local.memory
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = local.disk_gb
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  on_boot = true
  started = true

  initialization {
    datastore_id      = var.cloudinit_datastore
    user_data_file_id = proxmox_virtual_environment_file.user_data.id

    ip_config {
      ipv4 {
        address = var.monitoring_ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
