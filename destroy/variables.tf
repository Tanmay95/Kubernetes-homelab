variable "proxmox_api_url" {
  description = "The URL for the Proxmox API."
  type        = string
}

variable "proxmox_node" {
  description = "The Proxmox node to deploy to."
  type        = string
}

variable "proxmox_api_token" {
  description = "The Proxmox API token. Must be in the format 'USER@REALM!TOKENID=UUID'."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^!\\s]+![^=\\s]+=[0-9a-fA-F-]{8,}$", var.proxmox_api_token))
    error_message = "proxmox_api_token must be in the format 'USER@REALM!TOKENID=UUID' (e.g. terraform-prov@pve!mytoken=e4beb318-d048-4e12-8a7a-1ba2af373454)."
  }
}

variable "nodes" {
  description = "A list of virtual machines to target for destroy/import."
  type = list(object({
    name                    = string
    vmid                    = number
    role                    = string
    ip                      = string
    cores                   = number
    memory                  = number
    disk_size               = string
    tags                    = optional(list(string))
    additional_disk_size    = optional(string)
    additional_disk_storage = optional(string, "local")
  }))

  validation {
    condition     = length(var.nodes) > 0
    error_message = "The 'nodes' variable must contain at least one node."
  }

  # Defaults are the same as the main configuration to make importing simple
  default = [
    { name = "talos-control-01", vmid = 2000, role = "controlplane", ip = "192.168.1.101", cores = 2, memory = 2048, disk_size = "50G", tags = ["talos", "controlplane"] },
    { name = "talos-worker-01", vmid = 3000, role = "worker", ip = "192.168.1.102", cores = 4, memory = 3072, disk_size = "50G", additional_disk_size = "50G", additional_disk_storage = "local", tags = ["talos", "worker"] },
    { name = "talos-worker-02", vmid = 3001, role = "worker", ip = "192.168.1.103", cores = 4, memory = 3072, disk_size = "50G", additional_disk_size = "50G", additional_disk_storage = "local", tags = ["talos", "worker"] },
  ]
}

variable "talos_version" {
  description = "Talos version to use (e.g. v1.12.0)."
  type        = string
  default     = "v1.12.0"
}

variable "talos_iso_file" {
  description = "Default Proxmox storage reference to the uploaded Talos ISO for regular nodes (e.g. local:iso/talos-1.12.0.iso). If empty, a default path will be derived from talos_version."
  type        = string
  default     = ""
}

variable "disk_storage" {
  description = "Primary datastore ID for the main VM disk (e.g. local, local-zfs, zfs1)"
  type        = string
}

variable "additional_disk_storage" {
  description = "Datastore ID for any additional data disks (if nodes specify additional_disk_size)."
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Proxmox bridge to attach VM NICs to (e.g. vmbr0)."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Network gateway IP used for Talos machine configs (IPv4). Provide via cluster.auto.tfvars or TF_VAR_network_gateway."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.network_gateway))
    error_message = "network_gateway must be a valid IPv4 address (e.g. 192.168.1.1)."
  }
}
