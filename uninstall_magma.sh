#!/bin/bash

set -e

echo "⚠️ This script will uninstall all Magma components and reset K3s. Press Ctrl+C to cancel, or wait 5 seconds to proceed..."
sleep 5

# Uninstall Helm releases
echo "Uninstalling Helm releases..."
helm uninstall orc8r -n orc8r --ignore-not-found
helm uninstall orc8r-postgres -n db --ignore-not-found
helm uninstall nms-mysql -n db --ignore-not-found
helm uninstall cert-manager -n cert-manager --ignore-not-found

# Delete namespaces
echo "Deleting namespaces..."
kubectl delete namespace orc8r --ignore-not-found
kubectl delete namespace db --ignore-not-found
kubectl delete namespace cert-manager --ignore-not-found

# Remove K3s (this also removes all Kubernetes resources)
echo "Uninstalling K3s..."
/usr/local/bin/k3s-uninstall.sh || echo "K3s not found or already uninstalled"

# Clean up local files
echo "Removing local configuration files..."
rm -rf ~/.kube/config
rm -rf magma

# Remove KUBECONFIG from .bashrc
echo "Cleaning up .bashrc..."
sed -i '/export KUBECONFIG=$HOME\/.kube\/config/d' ~/.bashrc

echo "✅ Reset complete! Your environment has been cleaned up."
