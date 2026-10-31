# k3s Proxmox nodes, managed by Terraform.
#
# Three VMs -- server (control plane) on NUC-1, agents (workers) on NUC-2 and
# NUC-3 -- as full clones of the Ubuntu 24.04 cloud-init templates built by
# build-template.sh.
# Cloud-init (via snippets) installs the qemu guest agent + Tailscale and sets
# lab-net IPs. You run `tailscale up` once per VM by hand afterwards — no
# Tailscale auth keys are committed anywhere in this repo.

locals {
  # CPU types: nodes that may migrate across hosts use x86-64-v2-AES, the
  # fleet common denominator. The first agent runs "host" because the
  # Factorio server is pinned to it and needs full CPU performance.
  nodes = {
    server = {
      node_name   = var.proxmox_node_server
      hostname    = "k3s-server"
      template_id = 9000
      cores       = 4
      memory      = 16384
      disk_gb     = 120
      ip          = var.server_ip
      cpu_type    = "x86-64-v2-AES"
    }
    agent = {
      node_name   = var.proxmox_node_agent
      hostname    = "k3s-agent"
      template_id = 9001
      cores       = 4
      memory      = 16384
      disk_gb     = 120
      ip          = var.agent_ip
      cpu_type    = "host"
    }
    agent2 = {
      node_name   = var.proxmox_node_agent2
      hostname    = "k3s-agent2"
      template_id = 9002
      cores       = 4
      memory      = 16384
      disk_gb     = 120
      ip          = var.agent2_ip
      cpu_type    = "x86-64-v2-AES"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure_tls
  # Auth via env var: PROXMOX_VE_API_TOKEN="user@realm!token-id=secret"
  # (Datacenter → Permissions → API Tokens). Never commit the token.
}

resource "proxmox_virtual_environment_file" "user_data" {
  for_each     = local.nodes
  content_type = "snippets"
  datastore_id = var.cloudinit_datastore
  node_name    = each.value.node_name

  source_raw {
    file_name = "k3s-${each.key}-user-data.yaml"
    data = templatefile("${path.module}/files/user-data.yaml.tftpl", {
      hostname = each.value.hostname
      username = var.ssh_username
      ssh_keys = var.ssh_public_keys
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  for_each = local.nodes

  name            = each.value.hostname
  description     = "k3s ${each.key} node -- managed by Terraform (k8s/terraform)"
  tags            = ["k3s", "terraform"]
  node_name       = each.value.node_name
  stop_on_destroy = true
  # vm_id omitted → Proxmox assigns the next free ID.

  clone {
    vm_id = each.value.template_id
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = each.value.disk_gb
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

  initialization {
    datastore_id      = var.cloudinit_datastore
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }
  }
}
