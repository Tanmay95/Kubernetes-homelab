Destroy workflow (Terraform-based)

This folder contains a Terraform configuration that mirrors the VM resource addresses from the main configuration so you can import existing VMs into this state and then run `terraform destroy` safely.

Quick steps

1) Create or copy a `terraform.tfvars` or `cluster.auto.tfvars` into `destroy/` with at least the following vars set:

   - `proxmox_api_url` (e.g. https://pve.example.com:8006)
   - `proxmox_api_token` (format: `USER@REALM!TOKENID=UUID`)
   - `proxmox_node` (the node name the VMs live on)
   - `disk_storage` (the datastore referenced by the VMs)

   You can also set these using environment variables: `TF_VAR_proxmox_api_url`, `TF_VAR_proxmox_api_token`, etc.

2) Initialize:

   cd destroy
   terraform init

3) Import the existing VMs into this configuration's state.
   For each node in your `nodes` list run (replace values):

   terraform import 'proxmox_virtual_environment_vm.vm["talos-control-01"]' '<PROXMOX_NODE>/<VMID>'

   Example:

   terraform import 'proxmox_virtual_environment_vm.vm["talos-control-01"]' 'pve-node/2000'

   Repeat for each VM (use the name keys from `var.nodes` as the index).

4) Confirm state and plan:

   terraform state list
   terraform plan

   The plan should show the resources in the state.

5) Destroy (will run an API-based verification after resources are removed):

   terraform destroy -auto-approve

   - During the destroy, a `null_resource` is configured to run a small API check per-VM after the VMs are removed; if the check finds any remaining VM the local-exec will exit non-zero and the destroy will fail.

6) Manual verification (optional):

   - Check the Proxmox UI, or run:

     curl -s -H "Authorization: PVEAPIToken=<TOKEN>" "https://<PVE_HOST>:8006/api2/json/nodes/<NODE>/qemu/<VMID>/status/current" | jq .

Notes & recommendations

- The recommended way to make `destroy` automatic (no per-VM imports) is to use a shared backend for state (e.g., an S3/remote backend) so the same state is accessible from multiple working directories (no import required).

- This approach imports existing resources into a fresh state and then destroys them; it is explicit and safe but requires running the `terraform import` commands once.

- The small API verification uses `curl` in a `local-exec` provisioner; the token is supplied via environment variables to avoid embedding it in the command line.
