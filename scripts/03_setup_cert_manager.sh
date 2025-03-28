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

# Function to setup cert-manager
setup_cert_manager() {
    echo "🔒 Setting up cert-manager..."
    
    # Check if cert-manager is already installed
    if kubectl get namespace cert-manager &> /dev/null; then
        echo "🔍 Checking existing cert-manager installation..."
        CERT_MANAGER_POD=$(kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
        
        if [ "$CERT_MANAGER_POD" != "not-found" ]; then
            POD_STATUS=$(kubectl get pod "$CERT_MANAGER_POD" -n cert-manager -o jsonpath='{.status.phase}')
            if [ "$POD_STATUS" == "Running" ]; then
                echo "✅ cert-manager is already installed and running. Skipping installation."
                return 0
            else
                echo "⚠️ cert-manager found but not running correctly. Status: $POD_STATUS"
                echo "🔄 Reinstalling cert-manager..."
                kubectl delete namespace cert-manager
                sleep 10
            fi
        fi
    fi
    
    # Add Jetstack Helm repository
    echo "📦 Adding Jetstack Helm repository..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    check_error "Failed to add Jetstack Helm repository"
    
    # Create cert-manager namespace
    echo "📁 Creating cert-manager namespace..."
    kubectl create namespace cert-manager || true
    
    # Install cert-manager
    echo "🚀 Installing cert-manager..."
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.5.3 \
        --set installCRDs=true \
        --wait
    check_error "Failed to install cert-manager"
    
    # Wait for cert-manager to be ready
    echo "⏳ Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=120s
    check_error "cert-manager pods did not reach ready state"
    
    # Verify installation
    echo "🔍 Verifying cert-manager installation..."
    kubectl get pods -n cert-manager
    check_error "cert-manager pods are not running"
    
    echo "✅ Cert-manager setup complete!"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    setup_cert_manager
}

# Run the script
main "$@" 