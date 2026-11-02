variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.0.2.10:8006/ (no default -- set yours)"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "immich_node" {
  description = "Proxmox node hosting the Immich VM -- proxmox3: it holds the fleet's 1 TB local drive, and the photo library is the one workload here that is hungry for exactly that"
  type        = string
  default     = "proxmox3"
}

variable "immich_vm_id" {
  description = "VMID for the Immich VM (verify it is free CLUSTER-WIDE first: ls /etc/pve/nodes/*/qemu-server/<id>.conf /etc/pve/nodes/*/lxc/<id>.conf on any host must find nothing -- qm config on one node only reads that node's folder and is NOT a freedom check)"
  type        = number
  default     = 113
}

variable "template_id" {
  description = "Ubuntu 24.04 cloud template ON immich_node -- with local storage the provider clones on the target node, so this ID must be that node's own template copy (9000/9001/9002 per node in this fleet)"
  type        = number
  default     = 9002
}

variable "vm_datastore" {
  description = "Datastore for the VM disks"
  type        = string
  default     = "local-lvm"
}

variable "cloudinit_datastore" {
  description = "Datastore holding the cloud-init snippets and config drive (needs the snippets + images content types)"
  type        = string
  default     = "local"
}

variable "gateway" {
  description = "Lab net gateway"
  type        = string
  default     = "192.0.2.1"
}

variable "dns_servers" {
  description = "DNS servers for the VM itself -- deliberately an upstream resolver; a photo service has no business depending on the LAN's own DNS experiments"
  type        = list(string)
  default     = ["1.1.1.1"]
}

variable "immich_ip" {
  description = "Immich VM address (CIDR) -- the next slot in the lab static block, chosen so the future re-IP maps it to the same last octet in the lab VLAN (the .24/.27 trick)"
  type        = string
  default     = "192.0.2.28/24"
}

variable "ssh_username" {
  description = "Username created by cloud-init on the VM"
  type        = string
  default     = "labuser"
}

variable "ssh_public_keys" {
  description = "SSH public keys for the cloud-init user (no default -- set yours)"
  type        = list(string)
}
