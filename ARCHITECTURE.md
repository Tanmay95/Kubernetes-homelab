# Architecture & Flow Diagrams

## **1. Current Architecture (Terraform Creates This)**

```
┌─────────────────────────────────────────────────────────────────┐
│                      PROXMOX HOST (8GB+ RAM)                     │
│                       IP: 192.168.1.10:8006                      │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    vmbr0 Bridge                          │   │
│  │                 Network: 192.168.1.0/24                 │   │
│  └────┬────────────────────────────────────────────────┬───┘   │
│       │                                                  │       │
│  ┌────▼──────────────┐  ┌────────────────┐  ┌──────────▼────┐  │
│  │  VM: talos-cp-01  │  │ VM: talos-w-01 │  │ VM: talos-w-02│  │
│  │  VMID: 2000       │  │ VMID: 3000     │  │ VMID: 3001    │  │
│  │  IP: .101 (TBD)   │  │ IP: .102 (TBD) │  │ IP: .103 (TBD)│  │
│  │  CPU: 2 cores     │  │ CPU: 4 cores   │  │ CPU: 4 cores  │  │
│  │  RAM: 2GB         │  │ RAM: 3GB       │  │ RAM: 3GB      │  │
│  │  Boot: Talos ISO  │  │ Boot: Talos    │  │ Boot: Talos   │  │
│  │  Role: Control    │  │ Boot: Talos    │  │ Boot: Talos   │  │
│  │  Disk: 50GB       │  │ Role: Worker   │  │ Role: Worker  │  │
│  │                   │  │ Disk: 50G+50G  │  │ Disk: 50G+50G │  │
│  └───────────────────┘  └────────────────┘  └───────────────┘  │
│                                                                   │
│  Storage: "local" datastore                                      │
│  Bridge: vmbr0 (Proxmox configured)                             │
│  Gateway: 192.168.1.3 (Your router)                             │
└─────────────────────────────────────────────────────────────────┘
```

**What Terraform Does:**
- Creates 3 VMs with specified CPU/RAM/Storage
- Boots from Talos ISO
- Attaches to vmbr0 bridge
- Ready for Talos machine config

---

## **2. Terraform Apply Flow**

```
START
  │
  ├─→ terraform init (download provider)
  │
  ├─→ terraform validate (check syntax)
  │
  ├─→ terraform plan (preview changes)
  │
  ├─→ terraform apply (CREATE VMs)
  │    │
  │    ├─→ Connect to Proxmox API ✓
  │    │
  │    ├─→ Check node "hydra" exists ✓
  │    │
  │    ├─→ Check storage "local" exists ✓
  │    │
  │    ├─→ Check ISO "talos-1.12.0.iso" exists ✓
  │    │
  │    ├─→ Create talos-control-01 VM
  │    │    └─→ Allocate 2 cores, 2GB RAM, 50GB disk
  │    │
  │    ├─→ Create talos-worker-01 VM
  │    │    └─→ Allocate 4 cores, 3GB RAM, 50G+50G disk
  │    │
  │    ├─→ Create talos-worker-02 VM
  │    │    └─→ Allocate 4 cores, 3GB RAM, 50G+50G disk
  │    │
  │    └─→ Output VM details
  │
  └─→ READY FOR TALOS SETUP
        (See TALOS_SETUP_GUIDE.md)
```

**Possible Failure Points:**
```
├─→ ❌ Proxmox API unreachable
├─→ ❌ Node "hydra" not found
├─→ ❌ Storage "local" not found
├─→ ❌ ISO file not found
├─→ ❌ VMID already exists
├─→ ❌ Not enough RAM
└─→ ❌ Network bridge missing
```

---

## **3. Complete Setup Timeline**

```
┌──────────────────────────────────────────────────────────────┐
│ T=0:00  terraform apply                                      │
│         ├─ Validate config                                   │
│         ├─ Connect to Proxmox                                │
│         └─ Create 3 VMs (takes 10-30 seconds)               │
├──────────────────────────────────────────────────────────────┤
│ T=0:30  VMs booting                                          │
│         ├─ Proxmox: VMs powered on                           │
│         ├─ BIOS: Boot sequence (disk → ISO)                 │
│         └─ Talos: ISO loading (takes 20-60 seconds)         │
├──────────────────────────────────────────────────────────────┤
│ T=2:00  VMs ready                                            │
│         ├─ Talos installer running                           │
│         ├─ Waiting for machine config                        │
│         └─ IPs: DHCP (temporary)                            │
├──────────────────────────────────────────────────────────────┤
│ T=3:00  Generate Talos config                               │
│         ├─ talosctl gen config (on your machine)            │
│         ├─ Creates: controlplane.yaml, worker.yaml          │
│         └─ Creates: talosconfig, kubeconfig                 │
├──────────────────────────────────────────────────────────────┤
│ T=4:00  Apply control plane config                          │
│         ├─ talosctl apply-config → talos-control-01         │
│         ├─ Talos installs disk, configures network          │
│         ├─ Kubernetes API starting (slow, takes 90s)        │
│         └─ etcd: initializing                               │
├──────────────────────────────────────────────────────────────┤
│ T=6:00  Apply worker configs                                │
│         ├─ talosctl apply-config → talos-worker-01          │
│         ├─ talosctl apply-config → talos-worker-02          │
│         ├─ Talos installs, configures network               │
│         └─ Kubelet starting                                 │
├──────────────────────────────────────────────────────────────┤
│ T=8:00  Bootstrap cluster                                   │
│         ├─ talosctl bootstrap (initialize etcd)             │
│         ├─ Kubernetes API fully online                      │
│         └─ CSR processing, joining nodes                    │
├──────────────────────────────────────────────────────────────┤
│ T=10:00 Cluster ready                                       │
│         ├─ kubectl get nodes → All Ready                    │
│         ├─ All pods Running                                 │
│         └─ Install CNI (Cilium)                             │
└──────────────────────────────────────────────────────────────┘

Total Time: ~10 minutes from terraform apply to working k8s cluster
```

---

## **4. Data Flow: IP Assignment**

```
User-Defined IPs (cluster.auto.tfvars):
192.168.1.101/102/103
  │
  ├─→ Stored in Terraform state
  │
  ├─→ Used in talconfig.yaml generation
  │
  ├─→ Applied via talosctl (machine config)
  │
  ├─→ VMs configure eth0 with static IP
  │
  └─→ Result: VMs have permanent IPs
     ├─ talos-control-01: 192.168.1.101:6443 (Kubernetes API)
     ├─ talos-worker-01: 192.168.1.102 (kubelet)
     └─ talos-worker-02: 192.168.1.103 (kubelet)
```

---

## **5. Kubernetes Cluster Architecture (After Setup)**

```
┌────────────────────────────────────────────────────────────┐
│         KUBERNETES CLUSTER (3-node, Talos-based)           │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │      CONTROL PLANE (talos-control-01)                │  │
│  │      Role: master                                    │  │
│  │      IP: 192.168.1.101:6443 (API)                   │  │
│  │                                                       │  │
│  │      ┌─ kube-apiserver                              │  │
│  │      ├─ etcd (cluster state)                        │  │
│  │      ├─ kube-controller-manager                     │  │
│  │      ├─ kube-scheduler                              │  │
│  │      └─ kubelet                                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                   │
│         ┌───────────────┼───────────────┐                   │
│         │               │               │                   │
│  ┌──────▼────────┐ ┌────▼──────┐ ┌────▼──────┐             │
│  │   WORKER-01   │ │ WORKER-02 │ │ CILIUM    │             │
│  │ 192.168.1.102 │ │ 192.168   │ │ (CNI)     │             │
│  │               │ │ 1.103     │ │           │             │
│  │ Kubelet ✓     │ │           │ │ Manages:  │             │
│  │ Container RT  │ │ Kubelet ✓ │ │ - Pods    │             │
│  │ Talos ✓       │ │ Container │ │ - Network │             │
│  │               │ │ RT ✓      │ │ - Security│             │
│  │ User Apps:    │ │ Talos ✓   │ │           │             │
│  │ - Cilium      │ │           │ │ Add later │             │
│  │ - CoreDNS     │ │ User Apps │ │           │             │
│  │ - (optional)  │ │ (when     │ │           │             │
│  │   ArgoCD      │ │  deployed)│ │           │             │
│  └───────────────┘ └───────────┘ └───────────┘             │
│                                                              │
│  All connected via: vmbr0 (Proxmox bridge)                 │
│  All using: static IPs (192.168.1.0/24)                    │
└────────────────────────────────────────────────────────────┘
```

---

## **6. File Structure After All Setup**

```
/home/ansible/terraform-proxmox/
│
├── Terraform Files (You have these)
│   ├── main.tf                    ← VM resource definitions
│   ├── variables.tf               ← Input variables
│   ├── locals.tf                  ← Local values
│   ├── cluster.auto.tfvars        ← Your cluster config
│   └── .terraform/                ← Provider binaries (after init)
│
├── Documentation (Created for you)
│   ├── CODE_REVIEW_SUMMARY.md     ← This review
│   ├── TALOS_SETUP_GUIDE.md       ← How to complete setup
│   ├── WILL_IT_WORK.md            ← Troubleshooting guide
│   └── ARCHITECTURE.md            ← This file
│
├── Terraform State (Created during apply)
│   ├── terraform.tfstate          ← VM details (SENSITIVE!)
│   └── terraform.tfstate.backup
│
└── Future Files (After Talos setup)
    ├── /home/ansible/talos-config/
    │   ├── talconfig.yaml         ← Your cluster definition
    │   ├── controlplane.yaml      ← Generated for control plane
    │   ├── worker.yaml            ← Generated for workers
    │   ├── talosconfig            ← Talosctl config (SENSITIVE!)
    │   └── kubeconfig             ← Kubectl config (SENSITIVE!)
    │
    └── .gitignore                 ← Add sensitive files
        ├── *.tfstate*
        ├── talosconfig
        ├── kubeconfig
        └── .terraform/
```

---

## **7. Success Criteria Checklist**

```
✅ terraform plan - No errors
   ├─ Syntax valid
   ├─ All variables resolved
   └─ 3 resources to create

✅ terraform apply - Succeeds
   ├─ Proxmox API reachable
   ├─ All checks pass
   ├─ 3 VMs created
   └─ Outputs generated

✅ VMs boot - Talos running
   ├─ Proxmox UI shows VMs on
   ├─ Console shows boot messages
   └─ Waiting for config

✅ Talos config applied - IPs assigned
   ├─ Static IPs configured
   ├─ Network working
   └─ Nodes can ping each other

✅ Cluster bootstrap - Kubernetes online
   ├─ Control plane initialized
   ├─ etcd running
   ├─ API server responding
   └─ kubectl get nodes works

✅ CNI installed - Networking ready
   ├─ Cilium pods running
   ├─ Pod-to-pod communication works
   └─ DNS resolving
```

---

## **Decision Tree: What to Do If Things Break**

```
Does terraform apply work?
├─ YES → Go to TALOS_SETUP_GUIDE.md
│
└─ NO → Check WILL_IT_WORK.md
    ├─ Error about node → Fix node name
    ├─ Error about storage → Fix storage ID
    ├─ Error about ISO → Upload ISO
    ├─ Error about bridge → Create bridge
    ├─ Error about RAM → Free up memory
    ├─ Error about VMID → Change VMID
    ├─ Error about credentials → Fix token
    └─ Connection error → Check Proxmox is running
```

---

**See also:**
- CODE_REVIEW_SUMMARY.md - Code quality review
- TALOS_SETUP_GUIDE.md - Step-by-step cluster setup
- WILL_IT_WORK.md - Detailed troubleshooting

