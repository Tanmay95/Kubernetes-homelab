# ✅ FINAL CHECKLIST - Before terraform apply

## **Pre-Apply Verification (Do These NOW)**

### **Part 1: Proxmox Host Verification**

Run these on your Proxmox host (SSH or console):

```bash
# 1️⃣ VERIFY NODE NAME
$ hostname -s
# Output should be: hydra
# If different, update cluster.auto.tfvars:
#   proxmox_node = "your-actual-nodename"

# 2️⃣ VERIFY STORAGE EXISTS
$ pvesm status
# Output should include:
# NAME      TYPE    CONTENT         ACTIVE
# local     dir     images,rootdir    1
# If "local" is missing, you need to create it or use a different storage name

# 3️⃣ VERIFY ISO FILE EXISTS
$ ls -lh /var/lib/vz/template/iso/ | grep talos
# Should show: talos-1.12.0.iso (or your version)
# If missing, download:
#   cd /var/lib/vz/template/iso
#   wget https://github.com/siderolabs/talos/releases/download/v1.11.0/talos-amd64.iso
#   mv talos-amd64.iso talos-1.12.0.iso

# 4️⃣ VERIFY NETWORK BRIDGE
$ ip link show vmbr0
# Should show interface vmbr0
# If missing, you need to create it in Proxmox UI

# 5️⃣ VERIFY FREE RAM
$ free -h
# Grep for "Mem:" line
# Should show at least 10GB available (free column)
# Example: Mem: 31Gi total, 12Gi used, 19Gi free ✓

# 6️⃣ VERIFY VMID AVAILABILITY
$ qm list | grep -E "2000|3000|3001"
# Should return NOTHING (empty output)
# If you see VMs with these IDs, pick different IDs in cluster.auto.tfvars

# 7️⃣ VERIFY GATEWAY CONNECTIVITY
$ ip route | grep default
# Output should show: default via 192.168.1.3 dev vmbr0 metric 1024
# If gateway is different from 192.168.1.3:
#   Update cluster.auto.tfvars:
#   network_gateway = "192.168.x.x" (your actual gateway)

# 8️⃣ VERIFY API TOKEN
$ curl -k -H "Authorization: PVEAPIToken=terraform-prov@pve!mytoken:e4beb318-d048-4e12-8a7a-1ba2af373454" \
  https://192.168.1.10:8006/api2/json/version
# Should return JSON with version info
# If 401 error: token is invalid
# If connection refused: check IP/port are correct

# 9️⃣ VERIFY IP AVAILABILITY
$ ping -c 1 192.168.1.101  # Should fail (not yet assigned)
$ ping -c 1 192.168.1.102  # Should fail (not yet assigned)
$ ping -c 1 192.168.1.103  # Should fail (not yet assigned)
# All should show "Destination Host Unreachable" (good!)
```

---

### **Part 2: Local Machine Verification**

Run these on your laptop/computer where you'll run terraform:

```bash
# 1️⃣ TERRAFORM INSTALLED
$ terraform --version
# Should show: Terraform v1.x.x
# If not installed: brew install terraform (macOS) or https://www.terraform.io/downloads

# 2️⃣ TERRAFORM INITIALIZED
$ cd /home/ansible/terraform-proxmox
$ ls -la | grep terraform
# Should show: .terraform/ directory
# If missing, run: terraform init

# 3️⃣ CONFIGURATION FILES EXIST
$ ls -la *.tf *.tfvars
# Should show:
# - main.tf
# - variables.tf
# - locals.tf
# - cluster.auto.tfvars

# 4️⃣ TERRAFORM SYNTAX VALID
$ terraform validate
# Should show: Success! Configuration is valid.
# If error: fix syntax and try again

# 5️⃣ API TOKEN CONFIGURED
$ grep proxmox_api_token cluster.auto.tfvars
# Should show: proxmox_api_token = "e4beb318-d048-4e12-8a7a-1ba2af373454"

# 6️⃣ API URL CONFIGURED
$ grep proxmox_api_url cluster.auto.tfvars
# Should show: proxmox_api_url = "https://192.168.1.10:8006/"

# 7️⃣ NODE NAME CONFIGURED
$ grep proxmox_node cluster.auto.tfvars
# Should show: proxmox_node = "hydra"
# (Or your actual node name)

# 8️⃣ PROXMOX REACHABLE
$ ping 192.168.1.10
# Should get replies
# If not: check network, firewall, Proxmox running

# 9️⃣ TERRAFORM PLAN WORKS
$ terraform plan -out=tfplan
# Should show: Plan: 3 to add, 0 to change, 0 to destroy
# If errors: read carefully and fix
```

---

## **Scoring Your Readiness**

Count how many ✅ you checked above:

| Score | Status | Recommendation |
|-------|--------|-----------------|
| 18/18 | ✅ READY | Run `terraform apply` NOW |
| 15-17 | ⚠️ MOSTLY READY | Check which 1-3 items failed |
| 12-14 | 🔴 NOT READY | Fix 4+ items before applying |
| <12 | ❌ STOP | Don't apply yet, fix issues first |

---

## **The 5-Minute Safety Review**

Before hitting `terraform apply`, do this final check:

```bash
# 1. Print current config
cat /home/ansible/terraform-proxmox/cluster.auto.tfvars

# 2. Check each critical value:
# ✓ proxmox_api_url = "https://192.168.1.10:8006/"
# ✓ proxmox_api_token = "e4beb318-d048-4e12-8a7a-1ba2af373454"
# ✓ proxmox_node = "hydra"
# ✓ disk_storage = "local"
# ✓ network_gateway = "192.168.1.3"
# ✓ Node IPs: 192.168.1.101, 102, 103
# ✓ Node VMIDs: 2000, 3000, 3001

# 3. Run one final plan
terraform plan | grep "Plan:"
# Should show: Plan: 3 to add, 0 to change, 0 to destroy

# 4. Confirm ready
echo "Ready to apply!"
```

---

## **GO/NO-GO Decision**

### **🟢 GO (Apply Now)**
If ALL of these are true:
- [ ] terraform validate passes
- [ ] terraform plan shows "Plan: 3 to add"
- [ ] Proxmox node name matches
- [ ] Storage "local" verified
- [ ] ISO file "talos-1.12.0.iso" verified
- [ ] Network bridge "vmbr0" verified
- [ ] At least 10GB free RAM
- [ ] VMIDs 2000, 3000, 3001 available
- [ ] API token works (curl test passes)

**Command:**
```bash
terraform apply
```

### **🟡 WAIT (Fix One Issue)**
If 1-2 items are unchecked:
- Fix the specific issue
- Re-run the failing check
- Then proceed to APPLY

**Example:**
```bash
# If storage is wrong:
ssh proxmox "pvesm status"
# Update cluster.auto.tfvars with correct storage name
terraform validate  # Recheck
terraform apply
```

### **🔴 STOP (Fix Multiple Issues)**
If 3+ items are unchecked:
- Read through WILL_IT_WORK.md
- Fix each issue methodically
- Recheck each one
- Only then proceed to APPLY

---

## **During terraform apply**

What to watch for:

```bash
# You should see:
terraform apply

# ... planning phase ...
Plan: 3 to add, 0 to change, 0 to destroy.

# ... confirmation ...
Do you want to perform these actions?

# Type: yes

# ... creation phase (1-2 minutes) ...
proxmox_virtual_environment_vm.vm["talos-control-01"]: Creating...
proxmox_virtual_environment_vm.vm["talos-control-01"]: Creation complete after 45s
proxmox_virtual_environment_vm.vm["talos-worker-01"]: Creating...
proxmox_virtual_environment_vm.vm["talos-worker-01"]: Creation complete after 42s
proxmox_virtual_environment_vm.vm["talos-worker-02"]: Creating...
proxmox_virtual_environment_vm.vm["talos-worker-02"]: Creation complete after 40s

# ... success ...
Apply complete! Resources added: 3, changed: 0, destroyed: 0.

Outputs:

vm_details = {
  "talos-control-01" = {
    cores    = 2
    iso_used = "local:iso/talos-1.12.0.iso"
    memory   = 2048
    role     = "controlplane"
    vmid     = 2000
    ip       = "192.168.1.101"
  }
  ...
}
```

**If you see this: ✅ SUCCESS! Move to TALOS_SETUP_GUIDE.md**

---

## **If Something Goes Wrong During Apply**

### **Apply fails with error:**

1. Read the error message carefully
2. Check WILL_IT_WORK.md for that specific error
3. Fix the issue
4. Run `terraform plan` to verify fix
5. Run `terraform apply` again

### **Apply partially completes:**

If 1 or 2 VMs created but then fails:

```bash
# Option 1: Retry
terraform apply  # It will continue from where it stopped

# Option 2: Start over
terraform destroy
# (Fix the issue)
terraform apply
```

### **Apply succeeds but VMs don't boot:**

1. Check Proxmox UI: Datacenter → Nodes → VM status
2. If VM is "Stopped": Click to start it manually
3. If VM is "Running": Check console (Proxmox UI)
4. Continue with TALOS_SETUP_GUIDE.md

---

## **After terraform apply - Next Steps**

Once you see the success message:

1. **Wait 2-3 minutes** - VMs booting up
2. **Open TALOS_SETUP_GUIDE.md** - Follow step-by-step
3. **Install talosctl** - You'll need this
4. **Generate machine config** - talosctl gen config
5. **Apply config to nodes** - talosctl apply-config
6. **Bootstrap cluster** - talosctl bootstrap
7. **Get kubeconfig** - talosctl kubeconfig
8. **Verify** - kubectl get nodes

---

## **Emergency Procedures**

### **Need to delete everything?**

```bash
terraform destroy -auto-approve
# This will delete all 3 VMs from Proxmox
```

### **Need to redeploy?**

```bash
terraform destroy -auto-approve
# (Fix the issue in cluster.auto.tfvars)
terraform apply
```

### **Terraform state corrupted?**

```bash
rm -rf .terraform
rm terraform.tfstate*
terraform init
terraform apply
```

---

## **Final Sign-Off**

```
Date: _______________
Operator: _______________

Checklist completed: ___/18
Ready to apply: YES / NO

If YES, proceed with:
$ cd /home/ansible/terraform-proxmox
$ terraform apply
```

---

**Print this document. Check off each item. Only proceed when all are ✅**

Good luck! 🚀

