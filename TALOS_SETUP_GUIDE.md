# Talos Kubernetes Cluster Setup Guide

This guide explains what happens after Terraform creates the VMs and how to configure them as a Kubernetes cluster.

---

## **Overview: What Terraform Does vs What Talos Does**

### **Terraform's Role** ✅
- Creates 3 Proxmox VMs (1 control plane + 2 workers)
- Boots VMs from Talos ISO
- Allocates CPU, RAM, storage
- Assigns network bridge (vmbr0)

### **Talos's Role** ⚠️ (YOU MUST DO THIS)
- Initializes Kubernetes control plane
- Configures etcd (cluster database)
- Sets up static IPs and networking
- Generates kubeconfig for cluster access
- Joins worker nodes to cluster

---

## **Step 1: Terraform Apply (VM Creation)**

```bash
cd /home/ansible/terraform-proxmox

# Initialize Terraform
terraform init

# Verify configuration
terraform plan

# Create the VMs
terraform apply
```

**Output:** 3 VMs running Talos ISO, waiting for machine config

---

## **Step 2: Generate Talos Machine Configuration**

You need `talosctl` (Talos CLI tool) and a cluster configuration.

### **2a. Install talosctl**

```bash
# macOS
brew install talos

# Linux
curl https://talos.dev/install | bash

# Verify
talosctl version
```

### **2b. Create Talos Configuration Directory**

```bash
mkdir -p /home/ansible/talos-config
cd /home/ansible/talos-config
```

### **2c. Generate Cluster Config**

Create a `talconfig.yaml` file:

```yaml
---
version: v1alpha1
debug: false
persist: true

cluster:
  name: proxmox-talos-cluster
  controlPlane:
    endpoint: https://192.168.1.101:6443  # Control plane IP
  clusterNetwork:
    dns:
      servers:
        - 192.168.1.3  # Your gateway/DNS server
    cni:
      name: cilium
  network:
    hostname: talos-control-01

nodes:
  # Control Plane
  - hostname: talos-control-01
    ipAddress: 192.168.1.101
    controlPlane: true
    installDisk: /dev/sda
    networkInterfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - address: 192.168.1.101/24
        gateway: 192.168.1.3
        mtu: 1500
        nameservers:
          - 192.168.1.3

  # Worker 1
  - hostname: talos-worker-01
    ipAddress: 192.168.1.102
    installDisk: /dev/sda
    networkInterfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - address: 192.168.1.102/24
        gateway: 192.168.1.3
        mtu: 1500
        nameservers:
          - 192.168.1.3

  # Worker 2
  - hostname: talos-worker-02
    ipAddress: 192.168.1.103
    installDisk: /dev/sda
    networkInterfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - address: 192.168.1.103/24
        gateway: 192.168.1.3
        mtu: 1500
        nameservers:
          - 192.168.1.3

patches: []
```

### **2d. Generate Machine Configs**

```bash
# This creates controlplane.yaml, worker.yaml, and talosconfig
talosctl gen config --with-docs --with-examples proxmox-talos-cluster https://192.168.1.101:6443

# Or use the talconfig.yaml method if using talos-contrib
talos-generate --config talconfig.yaml
```

---

## **Step 3: Apply Machine Configuration to Nodes**

### **3a. Connect to First VM (Control Plane)**

```bash
# Get the IP from Terraform output (or Proxmox console)
# The VM will have a temporary DHCP IP or be waiting

# Try to access console
talosctl console -n 192.168.1.101 -e
```

### **3b. Apply Controlplane Config**

```bash
talosctl apply-config \
  --insecure \
  --nodes 192.168.1.101 \
  --file controlplane.yaml
```

**Wait 1-2 minutes** for control plane to initialize.

### **3c. Apply Worker Configs**

```bash
talosctl apply-config \
  --insecure \
  --nodes 192.168.1.102 \
  --file worker.yaml

talosctl apply-config \
  --insecure \
  --nodes 192.168.1.103 \
  --file worker.yaml
```

**Wait 1-2 minutes** for workers to initialize and join cluster.

---

## **Step 4: Bootstrap Cluster & Get kubeconfig**

### **4a. Bootstrap the Control Plane**

```bash
talosctl bootstrap \
  --talosconfig talosconfig \
  --nodes 192.168.1.101
```

Wait 2-5 minutes for etcd and Kubernetes API to start.

### **4b. Retrieve kubeconfig**

```bash
talosctl kubeconfig \
  --talosconfig talosconfig \
  -n 192.168.1.101 \
  -e 192.168.1.101
```

This creates `kubeconfig` in current directory.

### **4c. Test Cluster Access**

```bash
export KUBECONFIG=$(pwd)/kubeconfig

# Check nodes
kubectl get nodes

# Expected output:
# NAME                   STATUS   ROLES           VERSION
# talos-control-01       Ready    control-plane   v1.xx.x
# talos-worker-01        Ready    <none>          v1.xx.x
# talos-worker-02        Ready    <none>          v1.xx.x

# Check pods
kubectl get pods -A
```

---

## **Step 5: Install CNI (Cilium)**

```bash
# Using Helm (recommended)
helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=strict

# Verify
kubectl get pods -n kube-system
```

---

## **Step 6: Install ArgoCD (Optional)**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Access ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Go to: https://localhost:8080

# Get default password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## **Troubleshooting Checklist**

| Issue | Solution |
|-------|----------|
| **VMs won't boot from ISO** | Check ISO file exists in Proxmox storage: `pvesm list local` |
| **Can't reach Talos API** | Check Proxmox node name matches in cluster.auto.tfvars |
| **Static IPs not assigned** | Verify network config in talconfig.yaml matches your network |
| **Cluster not forming** | Check all 3 VMs can ping each other: `talosctl interfaces -n 192.168.1.101` |
| **etcd not starting** | Check control plane has 2GB+ RAM (check Talos logs) |
| **Workers won't join** | Ensure control plane is fully initialized before joining workers |

---

## **Complete Command Sequence**

```bash
# 1. Create VMs
terraform apply

# 2. Wait 2 minutes, then generate config
talosctl gen config proxmox-talos-cluster https://192.168.1.101:6443

# 3. Apply config to nodes
talosctl apply-config --insecure --nodes 192.168.1.101 --file controlplane.yaml
sleep 120
talosctl apply-config --insecure --nodes 192.168.1.102 --file worker.yaml
talosctl apply-config --insecure --nodes 192.168.1.103 --file worker.yaml

# 4. Bootstrap
sleep 120
talosctl bootstrap --nodes 192.168.1.101

# 5. Get kubeconfig
sleep 120
talosctl kubeconfig -n 192.168.1.101 -e 192.168.1.101

# 6. Verify
kubectl get nodes
```

---

## **Key Files You'll Need**

```
/home/ansible/talos-config/
├── talconfig.yaml              # Your cluster definition
├── controlplane.yaml           # Generated for control plane
├── worker.yaml                 # Generated for workers
├── talosconfig                 # Generated talosctl config
└── kubeconfig                  # Your kubectl config (KEEP SAFE!)
```

---

## **Security Notes**

1. **kubeconfig is sensitive** - Don't commit to git
2. **talosconfig is sensitive** - Don't share
3. **API token in terraform.tfvars** - Use env variables in production
4. Change default ArgoCD password after first login
5. Enable RBAC and network policies

---

## **References**

- [Talos Documentation](https://www.talos.dev/)
- [Talos GitHub](https://github.com/siderolabs/talos)
- [Cilium Installation](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)

