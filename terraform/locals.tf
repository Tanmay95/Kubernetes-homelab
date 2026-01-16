locals {
  # Base configuration values - use reasonable defaults and derive from node data
  cluster_name  = "proxmox-talos-cluster"
  talos_version = var.talos_version # Configurable Talos version
  cni_name      = "cilium"
  # Default ISO path derived from talos_version if `var.talos_iso_file` isn't provided
  default_talos_iso = "local:iso/talos-${replace(var.talos_version, "^v", "")}.iso"

  # Network configuration
  # Use a guarded first node IP so empty `var.nodes` doesn't cause index errors
  first_node_ip    = try(var.nodes[0].ip, "")
  network_cidr     = local.first_node_ip != "" ? "${join(".", slice(split(".", local.first_node_ip), 0, 3))}.0/24" : null
  gateway          = var.network_gateway
  cluster_endpoint = local.first_node_ip != "" ? "https://${local.first_node_ip}:6443" : null # Use control plane IP as endpoint when available

  # Storage and network settings from variables
  network_bridge          = var.network_bridge
  disk_storage            = var.disk_storage
  additional_disk_storage = var.additional_disk_storage




  # Transform nodes from variables for use in resources
  all_nodes_transformed = {
    for node in var.nodes : node.name => {
      vmid                    = node.vmid
      name                    = node.name
      cores                   = node.cores
      memory                  = node.memory
      ip                      = node.ip
      gateway                 = local.gateway
      disk_size               = node.disk_size
      disk_storage            = local.disk_storage
      disk_type               = "scsi"
      onboot                  = true
      sockets                 = 1
      network_bridge          = local.network_bridge
      network_model           = "virtio"
      tags                    = lookup(node, "tags", [node.role])
      additional_disk_size    = lookup(node, "additional_disk_size", null)
      additional_disk_storage = lookup(node, "additional_disk_size", null) != null ? lookup(node, "additional_disk_storage", local.additional_disk_storage) : null
      role                    = node.role
      iso_file                = var.talos_iso_file != "" ? var.talos_iso_file : local.default_talos_iso
    }
  }

  # Node type configurations for different roles
  node_configs = {
    controlplane = {
      cpu_type       = "host"
      memory_balloon = false
      bios           = "seabios"
      boot_order     = ["scsi0", "ide2"] # Boot from disk first, then ISO
      description    = "Talos Control Plane Node - Managed by Terraform"
    }
    worker = {
      cpu_type       = "host"
      memory_balloon = false
      bios           = "seabios"
      boot_order     = ["scsi0", "ide2"] # Boot from disk first, then ISO
      description    = "Talos Worker Node - Managed by Terraform"
    }
  }
}
