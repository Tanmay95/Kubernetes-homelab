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

locals {
  # Minimal transformation copied from the main config so imports match resource addresses
  all_nodes_transformed = {
    for node in var.nodes : node.name => {
      vmid                    = node.vmid
      name                    = node.name
      cores                   = node.cores
      memory                  = node.memory
      ip                      = node.ip
      disk_size               = node.disk_size
      disk_storage            = var.disk_storage
      disk_type               = "scsi"
      onboot                  = true
      sockets                 = 1
      network_bridge          = var.network_bridge
      network_model           = "virtio"
      tags                    = lookup(node, "tags", [node.role])
      additional_disk_size    = lookup(node, "additional_disk_size", null)
      additional_disk_storage = lookup(node, "additional_disk_size", null) != null ? lookup(node, "additional_disk_storage", var.additional_disk_storage) : null
      role                    = node.role
      iso_file                = var.talos_iso_file != "" ? var.talos_iso_file : "local:iso/talos-${replace(var.talos_version, "^v", "")}.iso"
    }
  }
}

# Resource blocks mirror the create configuration so the same addresses can be used for `terraform import`
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.all_nodes_transformed

  name        = each.value.name
  node_name   = var.proxmox_node
  description = each.value.role
  tags        = each.value.tags
  vm_id       = each.value.vmid

  started = each.value.onboot
  bios    = "seabios"

  agent { enabled = true }
  boot_order = ["scsi0", "ide2"]

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "host"
  }

  memory { dedicated = each.value.memory }

  network_device {
    bridge = each.value.network_bridge
    model  = each.value.network_model
  }

  disk {
    interface    = "scsi0"
    datastore_id = each.value.disk_storage
    size         = tonumber(trimsuffix(each.value.disk_size, "G"))
    cache        = "none"
    discard      = "ignore"
    ssd          = false
  }

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

  cdrom {
    interface = "ide2"
    file_id   = each.value.iso_file
  }
}

# Post-destroy verification: runs during destroy, after the VM resources are destroyed (depends_on ensures ordering)
resource "null_resource" "verify_vm_destroy" {
  for_each = local.all_nodes_transformed

  # Ensure null_resource destruction occurs after VM resources are destroyed so the check verifies absence
  depends_on = [for r in values(proxmox_virtual_environment_vm.vm) : r]

  provisioner "local-exec" {
    when = destroy

    environment = {
      PROXMOX_API_TOKEN = var.proxmox_api_token
      PROXMOX_API_URL   = var.proxmox_api_url
    }

    command = <<EOT
status=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: PVEAPIToken=${PROXMOX_API_TOKEN}" "${PROXMOX_API_URL}/api2/json/nodes/${var.proxmox_node}/qemu/${each.value.vmid}/status/current") || true
if [ "$status" = "200" ]; then
  echo "ERROR: VM ${each.key} (vmid ${each.value.vmid}) still exists"
  exit 1
else
  echo "OK: VM ${each.key} (vmid ${each.value.vmid}) removed"
fi
EOT
  }
}
