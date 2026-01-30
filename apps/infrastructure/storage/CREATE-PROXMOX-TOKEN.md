# Instructions to create Proxmox API Token:
#
# Method 1: Via Proxmox Web UI
# 1. Login to Proxmox: https://192.168.1.3:8006
# 2. Go to: Datacenter → Permissions → API Tokens
# 3. Click "Add"
# 4. User: root@pam
# 5. Token ID: csi
# 6. Uncheck "Privilege Separation"
# 7. Click "Add"
# 8. COPY THE SECRET - it's only shown once!
#
# Method 2: Via SSH to Proxmox host
# ssh root@192.168.1.3
# pveum user token add root@pam csi --privsep 0
# 
# Then update proxmox-csi-secret.yaml with:
# - token_id: "root@pam!csi"
# - token_secret: "paste-your-secret-here"
#
# After updating the secret, run:
# kubectl apply -f proxmox-csi-secret.yaml
