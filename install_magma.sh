#!/bin/bash

set -e

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ORC8R_DOMAIN> <EMAIL>"
    exit 1
fi

ORC8R_DOMAIN=$1
EMAIL=$2

# System update and K3s installation
sudo apt update && sudo apt upgrade -y
curl -sfL https://get.k3s.io | sh -

# Configure kubectl for current user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
sudo chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Persist KUBECONFIG across sessions
if ! grep -q 'export KUBECONFIG=$HOME/.kube/config' ~/.bashrc; then
  echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
fi

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Clone Magma repo
git clone https://github.com/magma/magma.git
cd magma/orc8r/cloud/helm

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager || true
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.5.3 \
  --set installCRDs=true

# Export Helm setting
export HELM_EXPERIMENTAL_OCI=1

# Generate TLS certs and Kubernetes secrets
cd ../../tools/helm

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout orc8r.key \
  -out orc8r.crt \
  -subj "/CN=${ORC8R_DOMAIN}"

kubectl create namespace orc8r || true

kubectl -n orc8r create secret tls orc8r-cert \
  --cert=orc8r.crt \
  --key=orc8r.key || true

kubectl -n orc8r create secret generic orc8r-secrets \
  --from-literal=secret-key="$(openssl rand -hex 32)" || true

kubectl -n orc8r create secret generic bootstrapper-secret \
  --from-literal=bootstrapper.key="$(openssl rand -hex 32)" || true

kubectl -n orc8r create secret generic application-secrets \
  --from-literal=app_secret="$(openssl rand -hex 32)" || true

# Go back to the orc8r helm chart folder
cd ../../cloud/helm

# PATCH deprecated API version (policy/v1beta1 → policy/v1)
echo "Patching deprecated policy/v1beta1 to policy/v1 in Helm chart..."
grep -rl 'policy/v1beta1' ./orc8r | xargs sed -i 's|policy/v1beta1|policy/v1|g'

# Create Helm values file with required values
cat <<EOF > orc8r-values.yaml
domain: ${ORC8R_DOMAIN}
proxy:
  controller:
    service:
      type: NodePort
nginx:
  spec:
    hostname: ${ORC8R_DOMAIN}
EOF

# Install Orchestrator using patched chart and values file
helm dependency update orc8r
helm install orc8r ./orc8r -f orc8r-values.yaml

# Show pod and service status
kubectl get pods -A
kubectl get svc -A

echo "✅ Magma Orchestrator + NMS deployed successfully!"
echo "🌐 Access NMS at: https://${ORC8R_DOMAIN}"
