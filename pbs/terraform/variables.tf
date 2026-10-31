variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.0.2.10:8006/ (no default -- set yours)"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "pbs_node" {
  description = "Proxmox node hosting the PBS VM (the node with the USB backup drive attached)"
  type        = string
  default     = "proxmox"
}

variable "pbs_vm_id" {
  description = "VMID for the PBS VM (verify it is free first: qm config <id> should report no such VM)"
  type        = number
  default     = 101
}

variable "vm_datastore" {
  description = "Datastore for the PBS boot disk"
  type        = string
  default     = "local-lvm"
}

variable "pbs_iso" {
  description = "PBS installer ISO as a volume id on the node's ISO storage"
  type        = string
  default     = "local:iso/proxmox-backup-server_4.2-1.iso"
}
