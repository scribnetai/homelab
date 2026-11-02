# Immich photo archive VM, managed by Terraform.
#
# ONE VM on NUC-3 (proxmox3), cloned from that node's Ubuntu 24.04
# cloud template (the k3s/terraform pattern). Immich itself runs
# inside the VM as a Docker Compose stack (../docker-compose.yml) --
# the VM is the durable unit; the containers are a replaceable payload.
#
# Why proxmox3: it holds the fleet's 1 TB local drive. The photo
# library is the one workload in this lab that is hungry for exactly
# that, and the host is otherwise the lightest of the three.
#
# Why a VM and not the k3s cluster: the library must not live on
# Longhorn. Node disks there are small and every byte is stored three
# times; an archive workload wants one big simple disk, close to the
# service (the Techno Tim pattern this build follows).
#
# Two disks, deliberately:
#   scsi0  32 GB   OS + Docker + the Compose stack
#   scsi1  600 GB  /data -- the photo library AND the Immich database,
#                  one mount, one backup unit. Grows online later
#                  (qm resize) when the archive earns it.
#
# Backup posture (decided 2026-11-01): this VM is THE copy of the
# photo archive, and that is considered safe because the Proxmox
# Backup Server nightly job covers ALL VMs -- this disk lands on the
# PBS datastore every night. The offsite (S3) leg of that backup
# system is what turns "backed up" into "survives the house"; it is
# step 11 of ../../pbs/README.md and was deferred one week on
# 2026-11-01.
#
# CPU type is x86-64-v2-AES (D7 fleet standard): the VM must be
# migratable/restorable onto ANY host, never pinned to one CPU.
# (The data disk is on proxmox3's local storage, so a restore onto
# another host means restoring the disk from backup with it -- which
# is exactly the PBS story above.)
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
  cpu_type     = "x86-64-v2-AES"
  cores        = 4
  memory       = 8192
  disk_gb      = 32
  data_disk_gb = 600
  hostname     = "immich"
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
  node_name    = var.immich_node

  source_raw {
    file_name = "immich-user-data.yaml"
    data = templatefile("${path.module}/files/user-data.yaml.tftpl", {
      hostname = local.hostname
      username = var.ssh_username
      ssh_keys = var.ssh_public_keys
    })
  }
}

resource "proxmox_virtual_environment_vm" "immich" {
  name            = "immich"
  description     = "Immich photo archive (Docker Compose inside) -- managed by Terraform (immich/terraform)"
  tags            = ["immich", "terraform"]
  node_name       = var.immich_node
  vm_id           = var.immich_vm_id
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

  # The archive itself. Formatted + mounted at /data by hand after
  # the first boot (see ../README.md) -- Terraform creates the disk,
  # it does not own filesystems.
  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi1"
    size         = local.data_disk_gb
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
        address = var.immich_ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
