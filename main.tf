terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.82.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.all_nodes_transformed

  name        = each.value.name
  node_name   = var.proxmox_node
  description = local.node_configs[each.value.role].description
  tags        = each.value.tags
  vm_id       = each.value.vmid

  started = each.value.onboot
  bios    = local.node_configs[each.value.role].bios

  # Enable QEMU Guest Agent for better VM management
  agent {
    enabled = true
  }

  # Boot the disk first, then the ISO as fallback
  boot_order = local.node_configs[each.value.role].boot_order

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = local.node_configs[each.value.role].cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  # Network configuration with static IP support
  network_device {
    bridge = each.value.network_bridge
    model  = each.value.network_model
  }

  # Static IP Configuration Notes:
  # Talos assigns IPs via machine config, not Proxmox network settings.
  # The IPs defined in cluster.auto.tfvars are used for:
  # 1. Reference in Talos machine config
  # 2. DNS registration post-deployment
  # 3. Load balancer targets
  # Configure actual static IPs in your Talos machine config (taloscli)

  # Primary disk
  disk {
    interface    = "scsi0"
    datastore_id = each.value.disk_storage
    size         = tonumber(trimsuffix(each.value.disk_size, "G"))
    cache        = "none"
    discard      = "ignore"
    ssd          = false
  }

  # Additional disk for storage (worker nodes with additional_disk_size)
  dynamic "disk" {
    for_each = each.value.additional_disk_size != null ? [1] : []
    content {
      interface    = "scsi1"
      datastore_id = each.value.additional_disk_storage
      size         = tonumber(trimsuffix(each.value.additional_disk_size, "G"))
      cache        = "none"
      discard      = "ignore"
      ssd          = false
      file_format  = "raw"
    }
  }

  # Attach Talos ISO
  cdrom {
    interface = "ide2"
    file_id   = each.value.iso_file
  }

}

output "vm_details" {
  description = "Details of created VMs organized by role."
  value = {
    for k, v in proxmox_virtual_environment_vm.vm : k => {
      vmid     = v.vm_id
      ip       = local.all_nodes_transformed[k].ip
      role     = local.all_nodes_transformed[k].role
      cores    = v.cpu[0].cores
      memory   = v.memory[0].dedicated
      iso_used = local.all_nodes_transformed[k].iso_file
    }
  }
}

output "node_roles" {
  description = "Node roles and their configurations."
  value = {
    controlplane = [for k, v in local.all_nodes_transformed : k if v.role == "controlplane"]
    workers      = [for k, v in local.all_nodes_transformed : k if v.role == "worker"]
  }
}