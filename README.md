# Terraform → Proxmox → Talos VMs (homelab)

This repository uses Terraform to create a small set of Proxmox virtual machines intended to run Talos Linux (and then Kubernetes). Terraform helps here because it is declarative and stateful:

- You describe the desired VM shape once (CPU/RAM/disks/NIC/ISO/boot order).
- `terraform plan` shows exactly what will change before it changes.
- `terraform apply` makes Proxmox match the configuration.
- `terraform destroy` removes what was created (or you can use the separate [destroy/README.md](destroy/README.md) workflow if you’ve lost state).

Important scope note (based on the code in this repo): Terraform **creates VMs and attaches a Talos ISO**, but it **does not configure static IPs inside the guest**. Talos assigns IPs via Talos machine config, not via Proxmox NIC settings.

## What Terraform is doing here

Terraform (in [main.tf](main.tf) and [locals.tf](locals.tf)):

- Connects to Proxmox via the `bpg/proxmox` provider (version pinned in Terraform config).
- Creates one `proxmox_virtual_environment_vm` per entry in `var.nodes`.
- Sets VM IDs (`vm_id`) from the `vmid` field you provide.
- Configures:
  - QEMU guest agent enabled
  - BIOS: `seabios`
  - Boot order: disk first (`scsi0`), then ISO (`ide2`)
  - VM is started after apply (`started = true` via `onboot = true` in locals)
  - CPU type `host`, 1 socket, `cores` from tfvars
  - Dedicated RAM (`memory.dedicated`) from tfvars
  - NIC: bridge from tfvars, model `virtio`
  - Primary disk (`scsi0`): datastore from `disk_storage`, size parsed from `disk_size` by stripping a trailing `G` and converting to a number
  - Disk settings: `cache = "none"`, `discard = "ignore"`, `ssd = false`
  - Optional additional disk (`scsi1`): only for nodes that define `additional_disk_size`
  - Additional disk format: `file_format = "raw"`
  - CD-ROM ISO from `talos_iso_file` (or a derived default if you don’t set it)

Outputs in [main.tf](main.tf):

- `vm_details`: VMID, role, cores, memory, and the **IP value you provided in tfvars**.
- `node_roles`: the list of node names by role.

## Repository layout

- Root Terraform (create VMs)
  - [main.tf](main.tf)
  - [variables.tf](variables.tf)
  - [locals.tf](locals.tf)
  - [cluster.auto.tfvars](cluster.auto.tfvars) (example config currently checked in)

- Helper script (generate Talos/talhelper environment file)
  - [script/tfvars-to-talos-env.sh](script/tfvars-to-talos-env.sh)
  - [script/talenv.yaml](script/talenv.yaml) (generated output)

- Destroy workflow (when you don’t have the original state)
  - [destroy/main.tf](destroy/main.tf)
  - [destroy/variables.tf](destroy/variables.tf)
  - [destroy/README.md](destroy/README.md)

## Inputs (what you must set)

Terraform variables are defined in [variables.tf](variables.tf). This repo expects, at minimum:

- `proxmox_api_url` (e.g. `https://<pve-host>:8006/`)
- `proxmox_api_token` (validated format: `USER@REALM!TOKENID=UUID`)
- `proxmox_node` (the Proxmox node name to place VMs on)
- `disk_storage` (datastore id for VM disks; **must not be** `local`)
- `network_gateway` (IPv4 gateway; used later when generating Talos configs)
- `nodes` (the list of VMs)

Other variables you can set (all are defined in [variables.tf](variables.tf)):

- `network_bridge` (defaults to `vmbr0`)
- `additional_disk_storage` (defaults to `local-lvm`; used when a node sets `additional_disk_size` but does not override storage)
- `talos_iso_file` (if empty, a default ISO path is derived from `talos_version`)
- `talos_version` (defaults to `v1.12.0`; only used to derive a default ISO path)

Behavior notes from [locals.tf](locals.tf):

- `disk_storage` and `network_bridge` are applied globally to all nodes via `local.all_nodes_transformed`.
- `tags` default to `[node.role]` if not provided per node.
- `additional_disk_size` controls whether an extra disk (`scsi1`) is created.

The repo includes [cluster.auto.tfvars](cluster.auto.tfvars), which Terraform automatically loads because it matches `*.auto.tfvars`.

Security note: the checked-in [cluster.auto.tfvars](cluster.auto.tfvars) currently contains a `proxmox_api_token` value. Treat this as sensitive; rotate/remove it if it’s real in your environment.

## Current cluster definition (from cluster.auto.tfvars)

The VM list currently defined in [cluster.auto.tfvars](cluster.auto.tfvars) is:

| Name | Role | VMID | IP (for Talos config reference) | vCPU cores | RAM (MiB) | Primary disk | Additional disk |
|------|------|------|----------------------------------|------------|-----------|--------------|-----------------|
| `talos-control-01` | controlplane | 2000 | 192.168.1.101 | 2 | 2048 | 50G | (none) |
| `talos-worker-01`  | worker       | 3000 | 192.168.1.102 | 4 | 3072 | 50G | 50G |
| `talos-worker-02`  | worker       | 3001 | 192.168.1.103 | 4 | 3072 | 50G | 50G |

Datastores/Network from [cluster.auto.tfvars](cluster.auto.tfvars):

- Primary disk datastore: `disk_storage = "local-lvm"`
- Additional disk datastore: `additional_disk_storage = "local-lvm"` (and the worker nodes explicitly set `additional_disk_storage = "local-lvm"`)
- NIC bridge: `network_bridge = "vmbr0"`
- Gateway for Talos configs: `network_gateway = "192.168.1.3"`
- ISO reference attached as CD-ROM: `talos_iso_file = "local:iso/nocloud-amd64.iso"`

### Resource budget (computed from cluster.auto.tfvars)

Totals for the above node list:

- vCPU cores: $2 + 4 + 4 = 10$
- RAM: $2048 + 3072 + 3072 = 8192$ MiB ($\approx 8$ GiB)
- Primary disk: $50 + 50 + 50 = 150$ GiB
- Additional disks: $50 + 50 = 100$ GiB
- Total allocated disk (primary + additional): $150 + 100 = 250$ GiB

## Prerequisites

1) Proxmox

- Proxmox VE reachable at your `proxmox_api_url`.
- A Proxmox API token with permissions to create/manage VMs on the target node.
- Note: this Terraform config sets `insecure = true` in the provider blocks, which disables TLS certificate verification when talking to Proxmox.
- A datastore that supports VM images for `disk_storage` (the Terraform code validates that `disk_storage != "local"`).
- The Talos ISO present in Proxmox storage at the exact `talos_iso_file` you set.

2) Local tools

- Terraform installed.

Optional (used by the helper script + follow-on Talos config generation):

- `bash`, `sed`, `grep` (for [script/tfvars-to-talos-env.sh](script/tfvars-to-talos-env.sh))
- `talhelper` (only if you plan to use the generated `talenv.yaml` with talhelper)

## Quick start (create VMs)

From the repository root:

1) Review/edit your inputs in [cluster.auto.tfvars](cluster.auto.tfvars).

2) Initialize Terraform:

```bash
terraform init
```

3) Plan:

```bash
terraform plan
```

Optional: save a plan file:

```bash
terraform plan -out tfplan
```

4) Apply (create the VMs):

```bash
terraform apply
```

Or, if you saved `tfplan`:

```bash
terraform apply tfplan
```

5) Inspect outputs:

```bash
terraform output
terraform output vm_details
```

## Networking and IPs (important)

This repository intentionally does not set Proxmox-side static IP configuration for the VM NIC.

In [main.tf](main.tf), the `ip` field in `nodes` is used for:

- Reference in Talos machine config
- DNS registration post-deployment (as a concept; no DNS automation is implemented in this repo)
- Load balancer targets (as a concept; no load balancer resources are implemented in this repo)

To actually use static IPs, configure them in your Talos machine config (via `talosctl` or via `talhelper`, depending on your workflow).

## Generate talenv.yaml for talhelper (optional)

The script [script/tfvars-to-talos-env.sh](script/tfvars-to-talos-env.sh) reads [cluster.auto.tfvars](cluster.auto.tfvars) and generates [script/talenv.yaml](script/talenv.yaml).

Run it from the repository root:

```bash
bash script/tfvars-to-talos-env.sh -v
```

This writes `script/talenv.yaml` containing:

- `GATEWAY_IP` (from `network_gateway`)
- `CONTROL_PLANE_ENDPOINT_IP` (the first controlplane node’s IP found in `nodes`)
- Per-node variables like `TALOS_CONTROL_PLANE_IP_0`, `TALOS_WORKER_IP_1`, etc.

If you use talhelper, run it from the directory where your `talenv.yaml` lives (the script defaults to the `script/` directory output):

```bash
cd script
talhelper genconfig --env-file talenv.yaml
```

## Destroying the VMs

### Option A: destroy using the original state (simplest)

If you still have the Terraform state used to create the VMs (default local state in the repo directory), you can destroy from the root:

```bash
terraform destroy
```

### Option B: destroy using the destroy/ workflow (when state is missing)

Use the Terraform configuration in [destroy/main.tf](destroy/main.tf). This is designed to:

- Import existing VMs into a fresh state using the same resource addresses
- Then run `terraform destroy` safely
- Then run a post-destroy API check per VM (via `curl`) to confirm the VM no longer exists

Follow the step-by-step instructions in [destroy/README.md](destroy/README.md).

## Troubleshooting (repo-specific)

- **`disk_storage` validation error**: `disk_storage` cannot be `local` (directory storage doesn’t support VM images). Use something like `local-lvm` or another storage that supports `images`.
- **Talos ISO not found**: ensure the exact `talos_iso_file` reference exists in Proxmox storage (example in this repo: `local:iso/nocloud-amd64.iso`).
- **VM IDs collide**: `vmid` values must be unique in Proxmox.
- **Script output doesn’t match your expectations**: [script/tfvars-to-talos-env.sh](script/tfvars-to-talos-env.sh) parses `nodes = [ ... ]` from the tfvars file; keep the `nodes` list in standard HCL formatting.

## Provider and versions

- Terraform Proxmox provider: `bpg/proxmox` version `0.82.1` (pinned in [main.tf](main.tf) and [destroy/main.tf](destroy/main.tf)).

