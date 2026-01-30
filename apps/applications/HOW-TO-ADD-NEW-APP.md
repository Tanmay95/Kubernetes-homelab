# 🚀 How to Add a New Application to Your Kubernetes Cluster

## Example: Adding Grafana Monitoring Dashboard

This guide shows you step-by-step how to add a new application to your cluster.

---

## 📋 Prerequisites

Before adding an app, you need:
- ✅ Gateway infrastructure is running (gateway-internal or gateway-external)
- ✅ You know which domain name to use (e.g., `grafana.starbasestudio.uk`)
- ✅ You know if it's internal (admin) or external (public) facing

---

## 🎯 Example: Adding Grafana

Let's add **Grafana** - an analytics and monitoring dashboard.

### Step 1: Create Application Folder Structure

```bash
cd /home/ansible/terraform-proxmox/apps/applications/
mkdir grafana
cd grafana
```

**Folder structure will be:**
```
apps/applications/grafana/
├── namespace.yaml          # Create isolated namespace
├── deployment.yaml         # Deploy Grafana pods
├── service.yaml           # Expose Grafana internally
├── http-route.yaml        # Route external traffic to Grafana
├── pvc.yaml              # (Optional) Persistent storage
└── kustomization.yaml     # Tell Kubernetes which files to apply
```

---

### Step 2: Create `namespace.yaml`

**File:** `apps/applications/grafana/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: grafana
```

**What this does:**
- Creates isolated workspace for Grafana
- Keeps resources separated from other apps
- Enables RBAC and network policies per-app

---

### Step 3: Create `deployment.yaml`

**File:** `apps/applications/grafana/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: grafana
  labels:
    app: grafana
spec:
  replicas: 1                    # How many pods to run
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.2.3     # Container image
        ports:
        - containerPort: 3000               # Grafana listens on port 3000
          name: http
          protocol: TCP
        env:
        - name: GF_SERVER_ROOT_URL
          value: "https://grafana.starbasestudio.uk"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "changeme123"              # Change in production!
        resources:
          requests:
            cpu: 100m                       # Minimum CPU needed
            memory: 128Mi                   # Minimum RAM needed
          limits:
            cpu: 500m                       # Maximum CPU allowed
            memory: 512Mi                   # Maximum RAM allowed
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana       # Where Grafana stores data
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-pvc            # Reference to PVC below
```

**What this does:**
- Tells Kubernetes to run Grafana container
- Sets resource limits (CPU/RAM)
- Configures environment variables
- Mounts persistent storage for data

**Key fields to customize:**
- `replicas: 1` - Increase for high availability
- `image: grafana/grafana:10.2.3` - Change version as needed
- `GF_SECURITY_ADMIN_PASSWORD` - IMPORTANT: Use secrets in production!
- `resources` - Adjust based on your needs

---

### Step 4: Create `pvc.yaml` (Persistent Storage)

**File:** `apps/applications/grafana/pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-pvc
  namespace: grafana
spec:
  accessModes:
    - ReadWriteOnce                # Single node can read/write
  resources:
    requests:
      storage: 5Gi                 # Request 5GB of storage
  storageClassName: local-path     # Use your cluster's storage class
```

**What this does:**
- Requests persistent disk storage
- Ensures Grafana data survives pod restarts
- Stores dashboards, users, settings

**When to skip:**
- If app is stateless (no data to save)
- Using external database

---

### Step 5: Create `service.yaml`

**File:** `apps/applications/grafana/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: grafana
  labels:
    app: grafana
spec:
  type: ClusterIP              # Internal only (not LoadBalancer)
  ports:
  - port: 80                   # Service listens on port 80
    targetPort: 3000           # Forwards to container port 3000
    protocol: TCP
    name: http
  selector:
    app: grafana               # Targets pods with label app=grafana
```

**What this does:**
- Creates internal endpoint for Grafana
- Maps service port 80 → container port 3000
- Load balances across multiple pods (if replicas > 1)
- Gateway will route traffic to this Service

**Key fields:**
- `type: ClusterIP` - Internal only (Gateway provides external access)
- `port: 80` - What the Service exposes
- `targetPort: 3000` - Where container actually listens
- `selector: app: grafana` - Must match Deployment labels

---

### Step 6: Create `http-route.yaml` (MOST IMPORTANT!)

**File:** `apps/applications/grafana/http-route.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: grafana
spec:
  parentRefs:
    - name: gateway-external      # Which gateway to use
      namespace: gateway           # Gateway is in "gateway" namespace
      sectionName: https           # Use HTTPS listener (port 443)
  hostnames:
    - "grafana.starbasestudio.uk" # Domain name for this app
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /               # Match all paths (/, /dashboard, etc.)
      backendRefs:
        - name: grafana            # Service name (from service.yaml)
          port: 80                 # Service port (from service.yaml)
```

**What this does:**
- **THE MAGIC PIECE** - Makes app accessible from outside cluster
- Tells gateway: "Route grafana.starbasestudio.uk to grafana service"
- Enables HTTPS with automatic TLS termination

**Key decisions:**

#### Choose Gateway:
```yaml
# For PUBLIC apps (internet-facing):
parentRefs:
  - name: gateway-external         # IP: 192.168.1.102
    namespace: gateway
    sectionName: https             # Port 443, uses cert-starbase

# For INTERNAL apps (admin tools):
parentRefs:
  - name: gateway-internal         # IP: 192.168.1.101
    namespace: gateway
    sectionName: http              # Port 80 (or https for ArgoCD)
```

#### Set Hostname:
```yaml
hostnames:
  - "grafana.starbasestudio.uk"    # Your subdomain
```

#### Route to Service:
```yaml
backendRefs:
  - name: grafana                  # Must match Service name
    port: 80                       # Must match Service port
```

---

### Step 7: Create `kustomization.yaml`

**File:** `apps/applications/grafana/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: grafana

resources:
  - namespace.yaml
  - pvc.yaml
  - deployment.yaml
  - service.yaml
  - http-route.yaml
```

**What this does:**
- Lists all YAML files to apply
- Ensures resources are applied in correct namespace
- Used by ArgoCD or `kubectl apply -k`

**Order matters:**
1. namespace.yaml (must exist first)
2. pvc.yaml (needed before deployment)
3. deployment.yaml
4. service.yaml
5. http-route.yaml (references service)

---

### Step 8: Add to ArgoCD ApplicationSet

**File:** `apps/applications/applications-appset.yaml`

Add Grafana to the list of applications:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: applications
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - name: homepage
        path: apps/applications/homepage
      - name: grafana              # ← ADD THIS
        path: apps/applications/grafana  # ← AND THIS
  template:
    metadata:
      name: '{{name}}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/yourusername/terraform-proxmox.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{name}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

**What this does:**
- Tells ArgoCD to monitor the grafana folder
- Automatically deploys when you push to Git
- Keeps cluster in sync with Git (GitOps)

---

### Step 9: Deploy!

#### Option A: Using ArgoCD (GitOps - Recommended)

```bash
# 1. Commit and push to Git
git add apps/applications/grafana/
git commit -m "Add Grafana monitoring dashboard"
git push

# 2. ArgoCD automatically detects and deploys
# Check ArgoCD UI: https://argocd.starbasestudio.uk
```

#### Option B: Using kubectl (Manual)

```bash
# Apply all resources
kubectl apply -k apps/applications/grafana/

# Watch deployment progress
kubectl get pods -n grafana -w
```

---

### Step 10: Verify Deployment

```bash
# 1. Check namespace created
kubectl get namespace grafana

# 2. Check pods are running
kubectl get pods -n grafana
# Expected: grafana-xxxxx-xxxxx   1/1   Running

# 3. Check service created
kubectl get service -n grafana
# Expected: grafana   ClusterIP   10.x.x.x   80/TCP

# 4. Check HTTPRoute created
kubectl get httproute -n grafana
# Expected: grafana   ["grafana.starbasestudio.uk"]

# 5. Test internal connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://grafana.grafana.svc.cluster.local

# 6. Access from browser
# https://grafana.starbasestudio.uk
```

---

## 🎯 Quick Reference: File Template

### Minimal App (Stateless)

For simple apps without persistent storage:

```
my-new-app/
├── namespace.yaml      # Namespace
├── deployment.yaml     # Pods
├── service.yaml       # Internal endpoint
├── http-route.yaml    # External routing
└── kustomization.yaml # Orchestration
```

### Full App (Stateful)

For apps needing storage, config, secrets:

```
my-new-app/
├── namespace.yaml
├── configmap.yaml         # Configuration files
├── secret.yaml           # Passwords, API keys
├── pvc.yaml             # Persistent storage
├── deployment.yaml
├── service.yaml
├── http-route.yaml
└── kustomization.yaml
```

---

## 📝 Checklist: Adding Any New App

- [ ] **1. Choose app name** (lowercase, no spaces): `grafana`
- [ ] **2. Choose domain**: `grafana.starbasestudio.uk`
- [ ] **3. Choose gateway**: `gateway-internal` or `gateway-external`
- [ ] **4. Find container image**: `grafana/grafana:10.2.3`
- [ ] **5. Know container port**: `3000`
- [ ] **6. Create folder**: `apps/applications/grafana/`
- [ ] **7. Create 5 core files**: namespace, deployment, service, http-route, kustomization
- [ ] **8. Add to ApplicationSet**: Update `applications-appset.yaml`
- [ ] **9. Commit to Git**: `git add && git commit && git push`
- [ ] **10. Verify deployment**: `kubectl get pods -n grafana`

---

## 🔧 Customization Examples

### Example 1: Simple Static Website

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-website
  namespace: my-website
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-website
  template:
    metadata:
      labels:
        app: my-website
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
```

### Example 2: Database-Backed App

```yaml
# deployment.yaml - Add database connection
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: webapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: myapp:latest
        env:
        - name: DATABASE_URL
          value: "postgresql://postgres.database.svc.cluster.local:5432/mydb"
        - name: REDIS_URL
          value: "redis://redis.cache.svc.cluster.local:6379"
```

### Example 3: Multiple Paths

```yaml
# http-route.yaml - Route different paths to different services
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: gateway-external
      namespace: gateway
      sectionName: https
  hostnames:
    - "app.starbasestudio.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api                # API requests
      backendRefs:
        - name: backend-api
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /                   # Everything else
      backendRefs:
        - name: frontend
          port: 80
```

---

## 🚨 Common Mistakes to Avoid

### ❌ Mistake 1: Mismatched Labels
```yaml
# deployment.yaml
spec:
  selector:
    matchLabels:
      app: grafana      # This label...

# service.yaml
spec:
  selector:
    app: dashboard      # ❌ DOESN'T MATCH! Service won't find pods
```

**✅ Fix:** Ensure labels match exactly!

### ❌ Mistake 2: Wrong Ports
```yaml
# Container listens on 3000
containers:
  - containerPort: 3000

# But service targets 8080
service:
  targetPort: 8080      # ❌ WRONG PORT! Traffic won't reach container
```

**✅ Fix:** `targetPort` must match `containerPort`

### ❌ Mistake 3: Wrong Gateway Reference
```yaml
# App is in "grafana" namespace
metadata:
  namespace: grafana

# HTTPRoute references service in different namespace
backendRefs:
  - name: grafana
    namespace: monitoring  # ❌ WRONG! Service doesn't exist there
```

**✅ Fix:** HTTPRoute and Service must be in same namespace (or use cross-namespace refs)

### ❌ Mistake 4: Forgot to Add to ApplicationSet
```yaml
# Created all files but forgot to add to applications-appset.yaml
# Result: ArgoCD doesn't know about your app
```

**✅ Fix:** Always update ApplicationSet!

---

## 🎓 Understanding the Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. USER TYPES IN BROWSER                                    │
│    https://grafana.starbasestudio.uk                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. DNS RESOLUTION                                           │
│    grafana.starbasestudio.uk → 192.168.1.102 (gateway IP)  │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. GATEWAY RECEIVES REQUEST                                 │
│    gateway-external (HTTPS listener, port 443)              │
│    - Terminates TLS using cert-starbase                     │
│    - Checks HTTPRoute: "Who handles grafana.starbase*?"     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. HTTPROUTE MATCHES                                        │
│    HTTPRoute in "grafana" namespace says:                   │
│    "Route to Service: grafana, Port: 80"                    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. SERVICE LOAD BALANCES                                    │
│    Service "grafana" in "grafana" namespace                 │
│    - Selects healthy pod with label app=grafana             │
│    - Forwards to pod on port 3000                           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. POD PROCESSES REQUEST                                    │
│    Grafana container receives HTTP request                  │
│    - Generates dashboard HTML                               │
│    - Sends response back through same path                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Real-World Examples

### Add Uptime Kuma (Monitoring)

```bash
mkdir apps/applications/uptime-kuma
# Container: louislam/uptime-kuma:1
# Port: 3001
# Hostname: uptime.starbasestudio.uk
# Gateway: gateway-internal (internal tool)
```

### Add WordPress (Public Website)

```bash
mkdir apps/applications/wordpress
# Container: wordpress:latest
# Port: 80
# Hostname: blog.starbasestudio.uk
# Gateway: gateway-external (public site)
# Needs: MySQL database, PVC for uploads
```

### Add MinIO (Object Storage)

```bash
mkdir apps/applications/minio
# Container: minio/minio:latest
# Port: 9000 (API), 9001 (Console)
# Hostname: s3.starbasestudio.uk
# Gateway: gateway-external
# Needs: Large PVC for object storage
```

---

## 📚 Next Steps

1. **Try it yourself**: Add a simple app like `nginx` or `httpd`
2. **Experiment**: Change replicas, add environment variables
3. **Learn more**: Study existing apps in `my-apps/` folder
4. **Advanced**: Add ConfigMaps, Secrets, multiple containers

---

## ✅ Summary

To add any new app:

1. **Create folder**: `apps/applications/<app-name>/`
2. **Create 5 files**: namespace, deployment, service, http-route, kustomization
3. **Key decisions**: 
   - App name and domain
   - Which gateway (internal/external)
   - Container image and port
4. **Deploy**: Add to ApplicationSet + push to Git
5. **Verify**: Check pods running, access via browser

**The HTTPRoute is the bridge** that connects your application to the outside world!
