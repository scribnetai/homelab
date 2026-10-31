variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.0.2.10:8006/ (no default -- set yours)"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "pihole_node" {
  description = "Proxmox node hosting the Pi-hole VM"
  type        = string
  default     = "proxmox3"
}

variable "pihole_vm_id" {
  description = "VMID for the Pi-hole VM (verify it is free CLUSTER-WIDE first: ls /etc/pve/nodes/*/qemu-server/<id>.conf /etc/pve/nodes/*/lxc/<id>.conf on any host must find nothing -- qm config on one node only reads that node's folder and is NOT a freedom check)"
  type        = number
  default     = 105
}

variable "template_id" {
  description = "Ubuntu 24.04 cloud template ON pihole_node -- with local storage the provider clones on the target node, so this ID must be that node's own template copy (9000/9001/9002 per node in this fleet)"
  type        = number
  default     = 9002
}

variable "vm_datastore" {
  description = "Datastore for the VM disk"
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
  description = "DNS servers for the VM itself -- deliberately an upstream resolver, never the VM's own Pi-hole (a resolver must not depend on itself)"
  type        = list(string)
  default     = ["1.1.1.1"]
}

variable "pihole_ip" {
  description = "Pi-hole VM address (CIDR)"
  type        = string
  default     = "192.0.2.27/24"
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
