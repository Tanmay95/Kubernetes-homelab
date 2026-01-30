# Proxmox CSI Storage Setup Guide

**Complete guide from Talos configuration to working Grafana deployment**

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Step-by-Step Installation](#step-by-step-installation)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [Common Issues](#common-issues)
8. [Maintenance](#maintenance)

---

## Overview

### What is Proxmox CSI?

The Proxmox CSI (Container Storage Interface) Plugin allows Kubernetes to dynamically provision persistent storage volumes using Proxmox VE's storage backends. It eliminates manual volume creation and integrates directly with Proxmox's storage infrastructure.

### Why Proxmox CSI for This Setup?

**Our Environment:**
- 3-node Talos Linux cluster (1 control plane + 2 workers)
- Running on Proxmox VE hypervisor
- Proxmox has local-lvm storage available

**Why we chose Proxmox CSI over alternatives:**

| Feature | Proxmox CSI | NFS | Longhorn | Local Path |
|---------|-------------|-----|----------|------------|
| **Native Proxmox Integration** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Performance** | ⭐⭐⭐⭐⭐ Direct block | ⭐⭐ Network | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **High Availability** | ✅ Via Proxmox | ✅ Via NFS server | ✅ Built-in | ❌ No |
| **Setup Complexity** | ⭐⭐⭐ Medium | ⭐ Easy | ⭐⭐⭐⭐ Complex | ⭐ Easy |
| **Resource Overhead** | ⭐⭐ Low | ⭐ Very Low | ⭐⭐⭐⭐ High | ⭐ Very Low |
| **Snapshots** | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **Volume Expansion** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |

**Decision:** Proxmox CSI provides the best balance of performance, features, and integration with existing infrastructure.

---

## Prerequisites

### Required Information

Before starting, gather the following:

```bash
# 1. Proxmox host IP
Proxmox IP: 192.168.1.10

# 2. Available Proxmox storage pools
# Check with: ssh root@192.168.1.10 "pvesm status"
Available Storage:
  - local-lvm (LVM-Thin)
  - local (directory)

# 3. Proxmox cluster/region name
# Usually "pve" unless customized
Region: pve

# 4. Kubernetes nodes info
Control Plane: talos-control-01 (192.168.1.112)
Worker 1: talos-worker-01 (192.168.1.113)
Worker 2: talos-worker-02 (192.168.1.114)

# 5. Talos config location
Talos Config: /home/ansible/terraform-proxmox/talos/talconfig.yaml
Kubeconfig: /home/ansible/terraform-proxmox/talos/kubeconfig
```

### Required Tools

```bash
# Verify tools are installed
talosctl version  # Talos CLI
kubectl version   # Kubernetes CLI
helm version      # Helm (optional, we'll use kubectl)
talhelper version # Talos config generator
```

---

## Architecture

### How Proxmox CSI Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│                                                               │
│  ┌─────────────┐        ┌──────────────────────────────┐   │
│  │  Grafana    │───────▶│ PersistentVolumeClaim (PVC)  │   │
│  │   Pod       │        │   Request: 1Gi storage       │   │
│  └─────────────┘        └────────────┬─────────────────┘   │
│                                      │                       │
│                                      ▼                       │
│                         ┌────────────────────────┐          │
│                         │  CSI Controller        │          │
│                         │  (Proxmox CSI Plugin)  │          │
│                         └────────┬───────────────┘          │
│                                  │ API Call                 │
└──────────────────────────────────┼──────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│                      Proxmox VE Host                          │
│                                                               │
│  API receives request → Creates VM disk → Attaches via iSCSI │
│                                                               │
│  Storage Pool: local-lvm (LVM-Thin)                          │
│  Creates: vm-XXX-disk-YYY                                    │
└──────────────────────────────────────────────────────────────┘
                                   │
                                   │ iSCSI mount
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│              Worker Node (talos-worker-01)                    │
│                                                               │
│  iSCSI initiator → Mounts volume → Pod uses storage          │
└──────────────────────────────────────────────────────────────┘
```

### Components

1. **CSI Controller** (Deployment):
   - Runs on any node
   - Communicates with Proxmox API
   - Creates/deletes volumes
   - 5 containers: controller, attacher, provisioner, resizer, liveness-probe

2. **CSI Node Plugin** (DaemonSet):
   - Runs on each worker node
   - Handles iSCSI connections
   - Mounts volumes to pods
   - 3 containers: node driver, registrar, liveness-probe

3. **StorageClass**:
   - Defines storage parameters
   - References Proxmox storage pool
   - Sets filesystem type (xfs/ext4)

---

## Step-by-Step Installation

### Step 1: Configure Talos for iSCSI Support

**Why this step is needed:**
- Proxmox CSI uses iSCSI to attach storage volumes to worker nodes
- Talos Linux is minimal by default and doesn't include iSCSI tools
- We need to enable the `iscsi_tcp` kernel module

**File:** `/home/ansible/terraform-proxmox/talos/talconfig.yaml`

```yaml
# Global patches (applies to all nodes)
patches:
# ... existing patches ...

# iSCSI support for Proxmox CSI
# This kernel module enables iSCSI protocol support
# Required for CSI to attach Proxmox volumes to nodes
- |-
  machine:
    kernel:
      modules:
        - name: iscsi_tcp  # Enables iSCSI over TCP/IP
```

**What this does:**
- Loads `iscsi_tcp` kernel module on boot
- Enables nodes to connect to Proxmox storage via iSCSI
- No reboot needed for in-place config changes

**Apply the configuration:**

```bash
# Step 1: Regenerate Talos configs from updated talconfig.yaml
cd /home/ansible/terraform-proxmox/talos
talhelper genconfig --env-file talenv.yaml

# Output:
# generated config for talos-control-01 in ./clusterconfig/...
# generated config for talos-worker-01 in ./clusterconfig/...
# generated config for talos-worker-02 in ./clusterconfig/...

# Step 2: Apply to control plane (does not require reboot)
export TALOSCONFIG=/home/ansible/terraform-proxmox/talos/clusterconfig/talosconfig
talosctl --nodes 192.168.1.112 apply-config \
  --file clusterconfig/proxmox-talos-lab-cluster-talos-control-01.yaml

# Expected: "Applied configuration without a reboot"

# Step 3: Apply to worker nodes
talosctl --nodes 192.168.1.113 apply-config \
  --file clusterconfig/proxmox-talos-lab-cluster-talos-worker-01.yaml

talosctl --nodes 192.168.1.114 apply-config \
  --file clusterconfig/proxmox-talos-lab-cluster-talos-worker-02.yaml

# Step 4: Verify cluster is healthy
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig
kubectl get nodes

# Expected output:
# NAME               STATUS   ROLES           AGE   VERSION
# talos-control-01   Ready    control-plane   22d   v1.33.3
# talos-worker-01    Ready    <none>          22d   v1.33.3
# talos-worker-02    Ready    <none>          22d   v1.33.3
```

**Why no reboot is needed:**
- Talos supports live kernel module loading
- Only machine config changes require reboot
- Kernel modules can be loaded dynamically

---

### Step 2: Create Proxmox API Token

**Why this step is needed:**
- CSI controller needs to authenticate with Proxmox API
- API token provides secure, limited-scope access
- Better security than using root password

**Create the token:**

```bash
# SSH to Proxmox host
ssh root@192.168.1.10

# Create API token for root user
# --privsep 0: Disables privilege separation (token has full user permissions)
pveum user token add root@pam csi --privsep 0

# Output:
# ┌──────────────┬──────────────────────────────────────┐
# │ key          │ value                                │
# ╞══════════════╪══════════════════════════════════════╡
# │ full-tokenid │ root@pam!csi                         │
# ├──────────────┼──────────────────────────────────────┤
# │ info         │ {"privsep":"0"}                      │
# ├──────────────┼──────────────────────────────────────┤
# │ value        │ 07402913-298a-4f47-9ac7-4bafeee606ba │ ← SAVE THIS!
# └──────────────┴──────────────────────────────────────┘

# IMPORTANT: Save these values:
# Token ID: root@pam!csi
# Token Secret: 07402913-298a-4f47-9ac7-4bafeee606ba
```

**What each parameter means:**
- `root@pam`: Proxmox user (root from PAM authentication)
- `csi`: Token name (descriptive identifier)
- `--privsep 0`: No privilege separation (token inherits all root permissions)

**Security note:**
- Token secret is shown only once
- Store securely (we'll put it in Kubernetes secret)
- Can be revoked anytime via `pveum user token remove root@pam csi`

---

### Step 3: Create Kubernetes Namespace and Secret

**Why this step is needed:**
- Isolates CSI components in dedicated namespace
- Stores Proxmox credentials securely
- Secret is mounted to CSI controller to authenticate API calls

**Create namespace:**

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Create dedicated namespace for CSI
kubectl create namespace csi-proxmox

# Why a dedicated namespace?
# - Isolation: Keeps CSI components separate
# - RBAC: Easier permission management
# - Organization: Clear separation of infrastructure components
```

**File:** `apps/infrastructure/storage/proxmox-csi-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: proxmox-csi-plugin
  namespace: csi-proxmox
type: Opaque
stringData:
  config.yaml: |
    clusters:
      # Array of Proxmox clusters (can have multiple)
      - url: https://192.168.1.10:8006/api2/json  # Proxmox API endpoint
        insecure: true  # Accept self-signed SSL certificates
        token_id: "root@pam!csi"  # API token ID from Step 2
        token_secret: "07402913-298a-4f47-9ac7-4bafeee606ba"  # Token secret
        region: pve  # Proxmox region/cluster name (default: pve)
```

**Configuration explained:**

- **url**: Proxmox API endpoint (always port 8006, path `/api2/json`)
- **insecure: true**: Required for self-signed certificates (homelab setup)
  - For production: Use proper SSL cert and set to `false`
- **token_id**: Full token identifier including user and token name
- **token_secret**: The secret value shown during token creation
- **region**: Proxmox cluster name
  - Check with: `ssh root@192.168.1.10 "pvecm status"` (if clustered)
  - Default standalone: `pve`

**Apply the secret:**

```bash
kubectl apply -f apps/infrastructure/storage/proxmox-csi-secret.yaml

# Verify
kubectl get secret -n csi-proxmox

# Output:
# NAME                  TYPE     DATA   AGE
# proxmox-csi-plugin    Opaque   1      5s
```

---

### Step 4: Install Proxmox CSI Plugin

**Why this step is needed:**
- Deploys CSI controller and node plugins
- Creates RBAC permissions
- Registers CSI driver with Kubernetes

**Installation method:**

We use the official manifest for Talos (includes necessary DaemonSet configurations):

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Apply official Proxmox CSI manifest for Talos
kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin-talos.yml

# This creates:
# - ServiceAccounts (controller & node)
# - RBAC roles and bindings
# - CSI controller deployment
# - CSI node daemonset
# - StorageClasses (we'll customize these)
# - CSIDriver registration
```

**What gets deployed:**

```bash
# Check components
kubectl get all -n csi-proxmox

# Expected:
# NAME                                                READY   STATUS    RESTARTS   AGE
# pod/proxmox-csi-plugin-controller-xxxxxxxxx-xxxxx   5/5     Running   0          2m
# pod/proxmox-csi-plugin-node-xxxxx                   3/3     Running   0          2m
# pod/proxmox-csi-plugin-node-yyyyy                   3/3     Running   0          2m

# NAME                                            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# deployment.apps/proxmox-csi-plugin-controller   1         1         1       1            1

# NAME                                      DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# daemonset.apps/proxmox-csi-plugin-node    2         2         2       2            2
```

**Component breakdown:**

1. **Controller Pod (5 containers):**
   - `proxmox-csi-plugin-controller`: Main CSI controller
   - `csi-attacher`: Attaches/detaches volumes
   - `csi-provisioner`: Creates/deletes volumes
   - `csi-resizer`: Handles volume expansion
   - `liveness-probe`: Health monitoring

2. **Node Pods (3 containers each):**
   - `proxmox-csi-plugin-node`: Handles iSCSI and mounts
   - `csi-node-driver-registrar`: Registers with kubelet
   - `liveness-probe`: Health monitoring

---

### Step 5: Configure Node Labels

**Why this step is needed:**
- CSI node plugin requires specific labels to start
- Labels help CSI identify node topology
- Required for proper volume scheduling

**Issue encountered:**

```bash
# Node daemonset shows 0 pods running
kubectl get ds -n csi-proxmox

# NAME                      DESIRED   CURRENT   READY
# proxmox-csi-plugin-node   0         0         0

# Why? Missing node selector label
# DaemonSet looks for: node.cloudprovider.kubernetes.io/platform=nocloud
```

**Solution - Add platform label:**

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Label worker nodes (where CSI node plugin runs)
kubectl label node talos-worker-01 \
  node.cloudprovider.kubernetes.io/platform=nocloud --overwrite

kubectl label node talos-worker-02 \
  node.cloudprovider.kubernetes.io/platform=nocloud --overwrite

# Why "nocloud"?
# - Talos VMs in Proxmox use NoCloud cloud-init datasource
# - This label tells CSI we're running on NoCloud platform
```

**Second issue encountered:**

```bash
# Pods start but crash
kubectl get pods -n csi-proxmox

# NAME                                            READY   STATUS             RESTARTS
# proxmox-csi-plugin-node-xxxxx                   2/3     CrashLoopBackOff   3

# Check logs
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node -c proxmox-csi-plugin-node

# Error: Failed to get region or zone for node: talos-worker-01
# Missing topology labels!
```

**Solution - Add topology labels:**

```bash
# Topology labels define node location in Proxmox cluster
# Format: topology.kubernetes.io/region=<proxmox-region>
#         topology.kubernetes.io/zone=<proxmox-zone>

# For all nodes (including control plane for proper scheduling)
kubectl label node talos-control-01 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

kubectl label node talos-worker-01 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

kubectl label node talos-worker-02 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

# Why these labels?
# - region: Proxmox cluster name (pve = default standalone)
# - zone: Availability zone within region (same as region for single-site)
# - Used for volume affinity and scheduling decisions
```

**Restart pods to pick up labels:**

```bash
# Delete pods (DaemonSet will recreate them)
kubectl delete pod -n csi-proxmox \
  -l app.kubernetes.io/name=proxmox-csi-plugin

# Wait and verify all pods are running
kubectl get pods -n csi-proxmox

# Expected: All pods 3/3 or 5/5 Running
# NAME                                            READY   STATUS    RESTARTS   AGE
# proxmox-csi-plugin-controller-xxxxxxxxx-xxxxx   5/5     Running   0          30s
# proxmox-csi-plugin-node-xxxxx                   3/3     Running   0          30s
# proxmox-csi-plugin-node-yyyyy                   3/3     Running   0          30s
```

---

### Step 6: Create Custom StorageClasses

**Why this step is needed:**
- Default StorageClasses use `storage: data` (doesn't exist in our Proxmox)
- We need to point to `storage: local-lvm` (our actual storage pool)
- StorageClass parameters cannot be modified (must recreate)

**Check Proxmox storage pools:**

```bash
ssh root@192.168.1.10 "pvesm status"

# Output:
# Name         Type     Status   Total       Used        Available    %
# local-lvm    lvmthin  active   364797952   82334897    282463054    22.57%
# local        dir      active   98497780    98132604    0            99.63%

# We'll use: local-lvm (LVM-Thin pool)
```

**File:** `apps/infrastructure/storage/storageclass.yaml`

```yaml
---
# StorageClass with XFS filesystem (recommended for Grafana/databases)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: proxmox-data-xfs
  annotations:
    # Set as default StorageClass
    # PVCs without storageClassName will use this
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.proxmox.sinextra.dev  # Proxmox CSI driver
parameters:
  storage: local-lvm  # MUST match Proxmox storage pool name
  csi.storage.k8s.io/fstype: xfs  # Filesystem type
  cache: directsync  # Proxmox cache mode for disk I/O
allowVolumeExpansion: true  # Allow PVC resize
reclaimPolicy: Delete  # Delete volume when PVC is deleted
volumeBindingMode: WaitForFirstConsumer  # Create volume when pod is scheduled
---
# StorageClass with ext4 filesystem (alternative option)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: proxmox-data
provisioner: csi.proxmox.sinextra.dev
parameters:
  storage: local-lvm
  csi.storage.k8s.io/fstype: ext4
  cache: writethrough
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

**Parameter explanations:**

**storage: local-lvm**
- MUST exactly match Proxmox storage pool name
- Check available pools: `pvesm status` on Proxmox host
- Common names: `local-lvm`, `local-zfs`, `ceph-pool`

**csi.storage.k8s.io/fstype: xfs**
- Filesystem created on the volume
- Options: `xfs`, `ext4`, `ext3`
- XFS: Better for large files, databases
- ext4: More stable, widely supported

**cache: directsync**
- How Proxmox caches disk I/O
- Options:
  - `directsync`: No cache, direct I/O (safest, slower)
  - `writethrough`: Cache reads, write directly (balanced)
  - `writeback`: Cache reads and writes (fastest, less safe)
  - `none`: No caching at all

**allowVolumeExpansion: true**
- Allows growing PVC size
- Example: Increase from 1Gi to 5Gi without recreating

**reclaimPolicy: Delete**
- What happens when PVC is deleted
- `Delete`: Remove volume from Proxmox (free space)
- `Retain`: Keep volume in Proxmox (manual cleanup needed)

**volumeBindingMode: WaitForFirstConsumer**
- When to create the volume
- `WaitForFirstConsumer`: Create when pod is scheduled (recommended for multi-node)
  - Ensures volume is created on the node where pod will run
- `Immediate`: Create immediately when PVC is created
  - May cause scheduling issues if volume is on wrong node

**Apply StorageClasses:**

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Delete old StorageClasses (created by manifest with wrong parameters)
kubectl delete storageclass proxmox-data-xfs proxmox-data

# Apply our custom StorageClasses
kubectl apply -f apps/infrastructure/storage/storageclass.yaml

# Verify
kubectl get storageclass

# Expected output:
# NAME                         PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
# proxmox-data                 csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer
# proxmox-data-xfs (default)   csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer
#                   ↑
#                   (default) means this is the default StorageClass
```

---

### Step 7: Fix Grafana PVC

**Why this step is needed:**
- Grafana pod was stuck because PVC couldn't provision
- Old PVC had no StorageClass specified
- Need to update PVC to use new StorageClass

**Original problem:**

```bash
kubectl get pvc -n grafana

# NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# grafana-pvc   Pending                                                     45m

kubectl describe pvc grafana-pvc -n grafana

# Events:
# Warning  FailedScheduling  pod has unbound immediate PersistentVolumeClaims
# 
# Why? No StorageClass available to provision volume
```

**File:** `apps/applications/grafana/pvc.yaml`

**Before:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""  # Empty = no StorageClass
  resources:
    requests:
      storage: 1Gi
```

**After:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: proxmox-data-xfs  # Use Proxmox CSI StorageClass
  resources:
    requests:
      storage: 1Gi
```

**Apply the fix:**

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Step 1: Delete old pending PVC
kubectl delete pvc grafana-pvc -n grafana

# Step 2: Apply updated PVC
# If using ArgoCD:
argocd app sync grafana

# Or manually:
kubectl apply -k apps/applications/grafana/

# Step 3: Verify PVC is bound
kubectl get pvc -n grafana

# Expected:
# NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# grafana-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO            proxmox-data-xfs

# Step 4: Verify pod is running
kubectl get pod -n grafana

# Expected:
# NAME                       READY   STATUS    RESTARTS   AGE
# grafana-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

**What happens behind the scenes:**

1. **PVC Created** → Kubernetes sees new PVC request
2. **CSI Controller Triggered** → Proxmox CSI controller receives request
3. **API Call to Proxmox** → Controller calls Proxmox API with credentials
4. **Volume Created** → Proxmox creates new LVM volume: `vm-XXX-disk-YYY`
5. **Pod Scheduled** → Kubernetes schedules Grafana pod to a node
6. **CSI Node Plugin** → Node plugin creates iSCSI connection
7. **Volume Attached** → iSCSI disk attached to node as block device
8. **Filesystem Created** → XFS filesystem created on the volume
9. **Volume Mounted** → Volume mounted to `/var/lib/grafana` in pod
10. **Pod Running** → Grafana starts and uses persistent storage

---

## Verification

### Complete System Check

**1. Verify CSI Components:**

```bash
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Check all CSI pods are running
kubectl get pods -n csi-proxmox

# Expected: All Running, no restarts
# proxmox-csi-plugin-controller-xxx   5/5     Running   0
# proxmox-csi-plugin-node-xxx         3/3     Running   0

# Check CSI driver registration
kubectl get csidriver

# Expected:
# NAME                        ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY
# csi.proxmox.sinextra.dev    true             true             false
```

**2. Verify StorageClasses:**

```bash
kubectl get storageclass

# Expected:
# NAME                         PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
# proxmox-data                 csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer
# proxmox-data-xfs (default)   csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer

# Check if default is set
kubectl get storageclass proxmox-data-xfs -o jsonpath='{.metadata.annotations}'

# Should include: "storageclass.kubernetes.io/is-default-class":"true"
```

**3. Verify Node Labels:**

```bash
# Check all required labels are present
kubectl get nodes --show-labels | grep -E 'platform|topology'

# Expected labels on all nodes:
# node.cloudprovider.kubernetes.io/platform=nocloud
# topology.kubernetes.io/region=pve
# topology.kubernetes.io/zone=pve
```

**4. Test Volume Creation:**

Create a test PVC to verify end-to-end functionality:

```bash
# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  storageClassName: proxmox-data-xfs
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status (will be Pending until pod uses it)
kubectl get pvc test-pvc

# Create test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo \$(date) >> /data/test.txt; sleep 5; done"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Wait and check PVC is bound
kubectl get pvc test-pvc

# Expected:
# NAME       STATUS   VOLUME                                     CAPACITY
# test-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi

# Check pod is running
kubectl get pod test-pod

# Expected:
# NAME       READY   STATUS    RESTARTS   AGE
# test-pod   1/1     Running   0          1m

# Verify data is being written
kubectl exec test-pod -- cat /data/test.txt

# Should show timestamps

# Check volume in Proxmox
ssh root@192.168.1.10 "pvesm list local-lvm | grep vm-"

# Should show new volume: vm-XXX-disk-YYY

# Clean up test resources
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

**5. Verify Grafana:**

```bash
# Check Grafana PVC
kubectl get pvc -n grafana

# Expected:
# NAME          STATUS   VOLUME       CAPACITY   STORAGECLASS
# grafana-pvc   Bound    pvc-xxx...   1Gi        proxmox-data-xfs

# Check Grafana pod
kubectl get pod -n grafana

# Expected:
# NAME                       READY   STATUS    RESTARTS   AGE
# grafana-xxxxxxxxxx-xxxxx   1/1     Running   0          5m

# Check Grafana logs (should be normal, no storage errors)
kubectl logs -n grafana deployment/grafana --tail=20

# Access Grafana (if you have ingress/route configured)
# Or port-forward:
kubectl port-forward -n grafana svc/grafana 3000:3000

# Open: http://localhost:3000
```

---

## Troubleshooting

### Diagnostic Commands

**1. Check CSI Controller Logs:**

```bash
# Main controller logs
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller \
  -c proxmox-csi-plugin-controller --tail=50

# Common errors:
# - "connection refused": Proxmox API not reachable
# - "authentication failed": Wrong token ID or secret
# - "storage pool not found": Wrong storage name in StorageClass
```

**2. Check CSI Node Logs:**

```bash
# Node plugin logs (on specific node)
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node \
  -c proxmox-csi-plugin-node --tail=50

# Common errors:
# - "Failed to get region or zone": Missing topology labels
# - "iSCSI login failed": iSCSI kernel module not loaded
# - "mount failed": Filesystem issues
```

**3. Check PVC Events:**

```bash
kubectl describe pvc <pvc-name> -n <namespace>

# Look for Events section at bottom:
# Common issues:
# - "no storage class": StorageClass doesn't exist or not set as default
# - "failed to provision volume": CSI controller error
# - "waiting for first consumer": Normal with WaitForFirstConsumer mode
```

**4. Check Volume Attachment:**

```bash
# List all volume attachments
kubectl get volumeattachment

# Describe specific attachment
kubectl describe volumeattachment <attachment-name>

# Common issues:
# - AttachError: Can't attach volume to node
# - NodeSelectorConflict: Volume on wrong node
```

**5. Check Proxmox Side:**

```bash
# SSH to Proxmox host
ssh root@192.168.1.10

# List volumes in storage pool
pvesm list local-lvm | grep vm-

# Check specific volume
pvesm status local-lvm

# Check iSCSI targets
pvesm export local-lvm:vm-XXX-disk-YYY
```

---

## Common Issues

### Issue 1: PVC Stuck in Pending

**Symptoms:**
```bash
kubectl get pvc
# NAME   STATUS    VOLUME   CAPACITY
# my-pvc Pending
```

**Causes & Solutions:**

**A) No StorageClass:**
```bash
# Check if StorageClass exists
kubectl get storageclass

# Solution: Create StorageClass (see Step 6)
```

**B) StorageClass not default and not specified in PVC:**
```yaml
# PVC should either:
# 1. Specify storageClassName
spec:
  storageClassName: proxmox-data-xfs

# 2. Or have a default StorageClass
kubectl patch storageclass proxmox-data-xfs \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**C) CSI Controller not running:**
```bash
# Check controller
kubectl get pods -n csi-proxmox

# If not running, check logs
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller
```

**D) Wrong Proxmox storage pool:**
```bash
# Check StorageClass parameter
kubectl get storageclass proxmox-data-xfs -o yaml | grep storage

# Compare with available pools
ssh root@192.168.1.10 "pvesm status"

# Fix: Recreate StorageClass with correct pool name
```

---

### Issue 2: CSI Node Pods CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods -n csi-proxmox
# proxmox-csi-plugin-node-xxx   2/3   CrashLoopBackOff
```

**Check logs:**
```bash
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node \
  -c proxmox-csi-plugin-node --tail=30
```

**A) Error: "Failed to get region or zone"**

**Cause:** Missing topology labels

**Solution:**
```bash
# Add labels to all nodes
kubectl label node talos-worker-01 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

kubectl label node talos-worker-02 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

kubectl label node talos-control-01 \
  topology.kubernetes.io/region=pve \
  topology.kubernetes.io/zone=pve --overwrite

# Restart pods
kubectl delete pod -n csi-proxmox -l app.kubernetes.io/name=proxmox-csi-plugin
```

**B) Error: "iSCSI command failed"**

**Cause:** iSCSI kernel module not loaded

**Solution:**
```bash
# Verify iSCSI module on node
export TALOSCONFIG=/home/ansible/terraform-proxmox/talos/clusterconfig/talosconfig
talosctl -n 192.168.1.113 read /proc/modules | grep iscsi

# If not present, check talconfig.yaml has iscsi_tcp module (Step 1)
# Regenerate and reapply configs
```

---

### Issue 3: Node DaemonSet Shows 0 Pods

**Symptoms:**
```bash
kubectl get ds -n csi-proxmox
# NAME                      DESIRED   CURRENT   READY
# proxmox-csi-plugin-node   0         0         0
```

**Cause:** Node selector label missing

**Solution:**
```bash
# Add platform label
kubectl label node talos-worker-01 \
  node.cloudprovider.kubernetes.io/platform=nocloud --overwrite

kubectl label node talos-worker-02 \
  node.cloudprovider.kubernetes.io/platform=nocloud --overwrite

# Verify
kubectl get ds -n csi-proxmox
# Should now show DESIRED=2, CURRENT=2
```

---

### Issue 4: "Authentication Failed" in Controller Logs

**Symptoms:**
```bash
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller
# Error: authentication failed: invalid ticket
```

**Causes & Solutions:**

**A) Wrong token secret:**
```bash
# Verify secret
kubectl get secret proxmox-csi-plugin -n csi-proxmox -o yaml

# Check token on Proxmox
ssh root@192.168.1.10 "pveum user token list root@pam"

# If needed, regenerate token (Step 2) and update secret
```

**B) Wrong token_id format:**
```yaml
# Correct format: "user@realm!tokenname"
token_id: "root@pam!csi"  # ✅ Correct
token_id: "root!csi"       # ❌ Missing @pam
token_id: "csi"            # ❌ Missing user
```

**C) Proxmox API not reachable:**
```bash
# Test from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -k https://192.168.1.10:8006/api2/json/version

# Should return JSON with Proxmox version
# If timeout: Check network/firewall
```

---

### Issue 5: Pod Can't Mount Volume

**Symptoms:**
```bash
kubectl describe pod <pod-name>
# Events:
# Warning  FailedMount  Unable to attach or mount volumes
```

**Check volume attachment:**
```bash
kubectl get volumeattachment

# Describe to see error
kubectl describe volumeattachment <name>
```

**A) Volume on wrong node:**

**Cause:** Volume created before pod scheduled (Immediate binding mode)

**Solution:** Use `WaitForFirstConsumer` in StorageClass:
```yaml
volumeBindingMode: WaitForFirstConsumer  # ✅ Correct
```

**B) iSCSI connection failed:**

**Check node logs:**
```bash
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node \
  -c proxmox-csi-plugin-node | grep -i iscsi
```

**Verify iSCSI on node:**
```bash
export TALOSCONFIG=/home/ansible/terraform-proxmox/talos/clusterconfig/talosconfig
talosctl -n 192.168.1.113 read /sys/class/iscsi_host
```

---

### Issue 6: "Storage Pool Not Found"

**Symptoms:**
```bash
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller
# Error: storage 'data' does not exist
```

**Cause:** StorageClass parameter doesn't match Proxmox storage pool

**Solution:**

**1. Check available storage on Proxmox:**
```bash
ssh root@192.168.1.10 "pvesm status"
# Name         Type     Status
# local-lvm    lvmthin  active  ← Use this name
# local        dir      active
```

**2. Update StorageClass:**
```yaml
parameters:
  storage: local-lvm  # Must match Proxmox exactly
```

**3. Recreate StorageClass:**
```bash
kubectl delete storageclass proxmox-data-xfs
kubectl apply -f apps/infrastructure/storage/storageclass.yaml
```

---

### Issue 7: Volume Expansion Fails

**Symptoms:**
```bash
# Expand PVC
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# PVC shows FileSystemResizePending
kubectl get pvc my-pvc
# STATUS   VOLUME   CAPACITY   ...   CONDITIONS
# Bound    pvc-xx   1Gi        ...   FileSystemResizePending
```

**Common causes:**

**A) allowVolumeExpansion not enabled:**

**Check StorageClass:**
```bash
kubectl get storageclass proxmox-data-xfs -o yaml | grep allowVolumeExpansion
# Should be: allowVolumeExpansion: true
```

**Fix:**
```bash
# Delete and recreate StorageClass with expansion enabled
# Note: Cannot modify existing StorageClass
```

**B) Pod needs restart:**

**Solution:**
```bash
# Delete pod to trigger filesystem resize
kubectl delete pod <pod-name>

# New pod will mount with expanded filesystem
kubectl get pvc my-pvc
# Should now show CAPACITY: 5Gi
```

---

## Maintenance

### Regular Checks

**Weekly:**

```bash
# 1. Check CSI pod health
kubectl get pods -n csi-proxmox

# 2. Check for storage capacity
ssh root@192.168.1.10 "pvesm status"

# 3. Check for failed PVCs
kubectl get pvc -A | grep -v Bound

# 4. Review CSI logs for errors
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller \
  --since=24h | grep -i error
```

**Monthly:**

```bash
# 1. Check volume count vs capacity
kubectl get pv | wc -l
ssh root@192.168.1.10 "pvesm list local-lvm | grep vm- | wc -l"

# 2. Review storage usage trends
kubectl top nodes

# 3. Verify backups (if configured)
```

---

### Backup Considerations

**PVC Data Backup:**

```bash
# Method 1: Volume snapshots (if enabled)
kubectl create volumesnapshot grafana-snapshot \
  --class proxmox-snapshot \
  --claim grafana-pvc \
  -n grafana

# Method 2: Pod-level backup
kubectl exec -n grafana deployment/grafana -- \
  tar czf /tmp/backup.tar.gz /var/lib/grafana

kubectl cp grafana/grafana-xxx:/tmp/backup.tar.gz ./backup.tar.gz
```

**Proxmox-level backup:**

```bash
# Identify VM disk for PVC
kubectl get pv pvc-xxx -o yaml | grep volumeHandle
# volumeHandle: local-lvm:vm-100-disk-1

# Create Proxmox backup
ssh root@192.168.1.10 "vzdump 100 --mode snapshot --storage local"
```

---

### Upgrading CSI Plugin

**Check for updates:**

```bash
# Check current version
kubectl get deployment -n csi-proxmox proxmox-csi-plugin-controller \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Latest version:
# https://github.com/sergelogvinov/proxmox-csi-plugin/releases
```

**Upgrade process:**

```bash
# 1. Review changelog
# https://github.com/sergelogvinov/proxmox-csi-plugin/blob/main/CHANGELOG.md

# 2. Update manifest
kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin-talos.yml

# 3. Verify upgrade
kubectl get pods -n csi-proxmox -w

# 4. Recreate StorageClasses (if parameters changed)
kubectl apply -f apps/infrastructure/storage/storageclass.yaml

# 5. Test with new PVC
```

---

### Decommissioning

**Remove CSI Plugin:**

```bash
# 1. Delete all PVCs first
kubectl get pvc -A
# Manually delete each PVC or application

# 2. Delete CSI components
kubectl delete namespace csi-proxmox

# 3. Remove StorageClasses
kubectl delete storageclass proxmox-data-xfs proxmox-data

# 4. Clean Proxmox API token
ssh root@192.168.1.10 "pveum user token remove root@pam csi"

# 5. Remove node labels (optional)
kubectl label node --all \
  node.cloudprovider.kubernetes.io/platform- \
  topology.kubernetes.io/region- \
  topology.kubernetes.io/zone-

# 6. Remove Talos config (optional)
# Edit talconfig.yaml and remove iscsi_tcp kernel module
# Regenerate and reapply
```

---

## Summary

### What We Accomplished

✅ **Configured Talos** for iSCSI support via kernel modules  
✅ **Created Proxmox API token** for secure CSI authentication  
✅ **Installed Proxmox CSI Plugin** with controller and node components  
✅ **Fixed node labels** for proper CSI pod scheduling  
✅ **Created StorageClasses** pointing to Proxmox local-lvm storage  
✅ **Fixed Grafana PVC** to use dynamic provisioning  
✅ **Verified** end-to-end storage workflow  

### Key Files Created/Modified

```
terraform-proxmox/
├── talos/
│   └── talconfig.yaml                           # Added iSCSI kernel module
├── apps/
│   ├── applications/
│   │   └── grafana/
│   │       └── pvc.yaml                         # Added storageClassName
│   └── infrastructure/
│       └── storage/
│           ├── namespace.yaml                   # CSI namespace
│           ├── proxmox-csi-secret.yaml          # Proxmox credentials
│           └── storageclass.yaml                # Custom StorageClasses
└── docs/
    └── STORAGE-SETUP-GUIDE.md                   # This document
```

### Architecture Overview

```
Applications (Grafana, etc.)
     ↓
PersistentVolumeClaim (1Gi, RWO)
     ↓
StorageClass (proxmox-data-xfs)
     ↓
Proxmox CSI Controller
     ↓ (API calls)
Proxmox VE (local-lvm storage)
     ↓ (iSCSI)
CSI Node Plugin on Worker
     ↓ (mount)
Pod Volume (/var/lib/grafana)
```

### Quick Reference Commands

```bash
# Set environment
export KUBECONFIG=/home/ansible/terraform-proxmox/talos/kubeconfig

# Check CSI status
kubectl get pods -n csi-proxmox
kubectl get storageclass
kubectl get pvc -A

# Check Grafana
kubectl get pod -n grafana
kubectl logs -n grafana deployment/grafana

# Debug CSI
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller -c proxmox-csi-plugin-controller
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node -c proxmox-csi-plugin-node

# Check Proxmox storage
ssh root@192.168.1.10 "pvesm status"
ssh root@192.168.1.10 "pvesm list local-lvm | grep vm-"
```

---

## Additional Resources

- **Proxmox CSI Plugin:** https://github.com/sergelogvinov/proxmox-csi-plugin
- **Talos Linux Documentation:** https://www.talos.dev/
- **Kubernetes CSI Spec:** https://kubernetes-csi.github.io/docs/
- **Proxmox VE Documentation:** https://pve.proxmox.com/pve-docs/

---

**Document Version:** 1.0  
**Last Updated:** January 30, 2026  
**Author:** GitHub Copilot  
**Environment:** Talos v1.11.0, Kubernetes v1.33.3, Proxmox VE
