# Storage Infrastructure - Proxmox CSI

This directory contains the Proxmox CSI storage configuration for the Kubernetes cluster.

## Files

- **namespace.yaml** - Creates `csi-proxmox` namespace for CSI components
- **proxmox-csi-secret.yaml** - Contains Proxmox API credentials (token)
- **storageclass.yaml** - Defines storage classes for dynamic provisioning

## Quick Start

```bash
# 1. Create namespace
kubectl apply -f namespace.yaml

# 2. Apply Proxmox credentials
kubectl apply -f proxmox-csi-secret.yaml

# 3. Install CSI plugin (one-time setup)
kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin-talos.yml

# 4. Label nodes (required for CSI to work)
kubectl label node talos-worker-01 node.cloudprovider.kubernetes.io/platform=nocloud topology.kubernetes.io/region=pve topology.kubernetes.io/zone=pve --overwrite
kubectl label node talos-worker-02 node.cloudprovider.kubernetes.io/platform=nocloud topology.kubernetes.io/region=pve topology.kubernetes.io/zone=pve --overwrite
kubectl label node talos-control-01 topology.kubernetes.io/region=pve topology.kubernetes.io/zone=pve --overwrite

# 5. Apply storage classes
kubectl apply -f storageclass.yaml

# 6. Verify
kubectl get pods -n csi-proxmox
kubectl get storageclass
```

## Configuration Details

### Proxmox API Secret

The secret contains connection details to Proxmox:
- **URL:** https://192.168.1.10:8006/api2/json
- **Token ID:** root@pam!csi
- **Region:** pve

### Storage Classes

Two storage classes are available:

1. **proxmox-data-xfs** (default)
   - Filesystem: XFS
   - Storage Pool: local-lvm
   - Cache: directsync
   - Use for: Databases, Grafana, general purpose

2. **proxmox-data**
   - Filesystem: ext4
   - Storage Pool: local-lvm
   - Cache: writethrough
   - Use for: Alternative filesystem option

## Usage in Applications

Add to your PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-storage
spec:
  storageClassName: proxmox-data-xfs  # or leave blank for default
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

## Troubleshooting

```bash
# Check CSI pods
kubectl get pods -n csi-proxmox

# Check logs
kubectl logs -n csi-proxmox deployment/proxmox-csi-plugin-controller -c proxmox-csi-plugin-controller
kubectl logs -n csi-proxmox ds/proxmox-csi-plugin-node -c proxmox-csi-plugin-node

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Verify Proxmox storage
ssh root@192.168.1.10 "pvesm status"
```

## Full Documentation

See [STORAGE-SETUP-GUIDE.md](../../docs/STORAGE-SETUP-GUIDE.md) for complete setup instructions and troubleshooting.
