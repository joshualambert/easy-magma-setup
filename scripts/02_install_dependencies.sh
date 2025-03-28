#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Function to enable verbose mode
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\n🔍 VERBOSE: $1"
    fi
}

# Function to check if a command succeeded
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: $1"
        exit 1
    fi
}

# Function to install system dependencies
install_dependencies() {
    echo "🔄 Updating system and installing K3s..."
    
    # Check if K3s is already installed
    if command -v k3s &> /dev/null; then
        echo "✅ K3s is already installed."
    else
        echo "🔄 Installing K3s..."
        sudo apt update -q && sudo apt upgrade -y -q
        curl -sfL https://get.k3s.io | sh -
        check_error "Failed to install K3s"
    fi

    echo "🔧 Configuring kubectl..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown "$USER":"$USER" ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG="$HOME/.kube/config"

    if ! grep -q "export KUBECONFIG=$HOME/.kube/config" ~/.bashrc; then
        echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
    fi

    # Check if Helm is already installed
    if command -v helm &> /dev/null; then
        echo "✅ Helm is already installed."
    else
        echo "⚓ Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        check_error "Failed to install Helm"
    fi
    
    # Verify dependencies
    echo "🔍 Verifying dependencies..."
    kubectl version --client
    check_error "kubectl is not configured properly"
    
    helm version
    check_error "Helm is not configured properly"
    
    # Test the connection to the K3s cluster
    echo "🔍 Testing Kubernetes cluster connection..."
    kubectl get nodes
    check_error "Cannot connect to Kubernetes cluster"
    
    echo "✅ System dependencies installed and verified successfully!"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    install_dependencies
}

# Run the script
main "$@" 