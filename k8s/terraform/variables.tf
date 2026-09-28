variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.168.128.10:8006/ (no default — set yours)"
  type        = string
}

variable "proxmox_insecure_tls" {
  description = "Skip TLS verification (Proxmox uses a self-signed cert by default)"
  type        = bool
  default     = true
}

variable "proxmox_node_server" {
  description = "Proxmox node hosting the k3s server VM (NUC-1)"
  type        = string
  default     = "proxmox"
}

variable "proxmox_node_agent" {
  description = "Proxmox node hosting the k3s agent VM (NUC-2)"
  type        = string
  default     = "proxmox2"
}

variable "template_id" {
  description = "VMID of the cloud-init template built by build-template.sh"
  type        = number
  default     = 9000
}

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "cloudinit_datastore" {
  description = "Datastore holding the cloud-init snippets and config drive"
  type        = string
  default     = "local"
}

variable "gateway" {
  description = "Lab net gateway"
  type        = string
  default     = "192.168.128.1"
}

variable "dns_servers" {
  description = "DNS servers for the nodes"
  type        = list(string)
  default     = ["1.1.1.1"]
}

variable "server_ip" {
  description = "k3s server VM address (CIDR)"
  type        = string
  default     = "192.168.128.21/24"
}

variable "agent_ip" {
  description = "k3s agent VM address (CIDR)"
  type        = string
  default     = "192.168.128.22/24"
}

variable "ssh_username" {
  description = "Username created by cloud-init on both VMs"
  type        = string
  default     = "scribnet"
}

variable "ssh_public_keys" {
  description = "SSH public keys for the cloud-init user (no default — set yours)"
  type        = list(string)
}
