variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.0.2.10:8006/ (no default -- set yours)"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "monitoring_node" {
  description = "Proxmox node hosting the monitoring VM -- proxmox2: it has the fleet's RAM headroom, and it is also the NUT server host (the UPS plugs into it), so the watcher lives with the watched"
  type        = string
  default     = "proxmox2"
}

variable "monitoring_vm_id" {
  description = "VMID for the monitoring VM (verify it is free CLUSTER-WIDE first: ls /etc/pve/nodes/*/qemu-server/<id>.conf /etc/pve/nodes/*/lxc/<id>.conf on any host must find nothing -- qm config on one node only reads that node's folder and is NOT a freedom check)"
  type        = number
  default     = 114
}

variable "template_id" {
  description = "Ubuntu 24.04 cloud template ON monitoring_node -- with local storage the provider clones on the target node, so this ID must be that node's own template copy (9000/9001/9002 per node in this fleet; proxmox2's is 9001)"
  type        = number
  default     = 9001
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
  description = "DNS servers for the VM itself -- deliberately an upstream resolver; a monitoring box must keep working (and keep resolving) while the LAN's own DNS is the patient"
  type        = list(string)
  default     = ["1.1.1.1"]
}

variable "monitoring_ip" {
  description = "Monitoring VM address (CIDR) -- the next slot in the lab static block"
  type        = string
  default     = "192.0.2.16/24"
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
