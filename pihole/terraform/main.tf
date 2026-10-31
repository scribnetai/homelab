# Pi-hole DNS VM, managed by Terraform.
#
# ONE small VM on NUC-3, cloned from that node's Ubuntu 24.04 cloud
# template (the k8s/terraform pattern). Pi-hole v6 itself runs inside
# the VM as a Docker Compose stack (../docker-compose.yml) -- the VM is
# the durable, migratable unit; the container is a replaceable payload.
#
# Why a VM and not the k3s cluster: DNS sits UNDER the cluster. If the
# house resolver lived in k3s, a cluster/storage outage would take
# down DNS with it -- a circular dependency. Why not on NUC-1: that
# host carries the backup stack (PBS VM + its USB datastore), and the
# whole point of this build window is zero contention with it.
#
# CPU type is x86-64-v2-AES (D7 fleet standard): a DNS server must be
# migratable/restorable onto ANY host, never pinned to one CPU.
#
# Cloud-init installs the qemu guest agent, Docker, and Tailscale.
# You run `tailscale up` once by hand afterwards -- no Tailscale auth
# keys are committed anywhere in this repo.
#
# Auth via env var: PROXMOX_VE_API_TOKEN (same token as the k3s and
# pbs modules), plus the provider's SSH leg (PROXMOX_VE_SSH_*) for the
# snippet upload -- plan never exercises the SSH leg, only apply does.
# Never commit the token. Real endpoint/IP values live only in the
# local terraform.tfvars (gitignored); this file carries doc-range
# defaults.

locals {
  cpu_type = "x86-64-v2-AES"
  cores    = 2
  memory   = 2048
  disk_gb  = 32
  hostname = "pihole"
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
  node_name    = var.pihole_node

  source_raw {
    file_name = "pihole-user-data.yaml"
    data = templatefile("${path.module}/files/user-data.yaml.tftpl", {
      hostname = local.hostname
      username = var.ssh_username
      ssh_keys = var.ssh_public_keys
    })
  }
}

resource "proxmox_virtual_environment_vm" "pihole" {
  name            = "pihole"
  description     = "Pi-hole v6 DNS ad-blocker (Docker Compose inside) -- managed by Terraform (pihole/terraform)"
  tags            = ["pihole", "terraform"]
  node_name       = var.pihole_node
  vm_id           = var.pihole_vm_id
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
        address = var.pihole_ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
