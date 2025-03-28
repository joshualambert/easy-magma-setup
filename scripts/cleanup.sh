#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Constants
CERTS_DIR="/tmp/magma_certs"
CUSTOM_CHART_DIR="/tmp/magma-custom-chart"

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

# Function to cleanup a failed installation
cleanup() {
    echo "🧹 Cleaning up failed installation..."
    
    # Delete Helm releases
    echo "🧹 Removing Helm releases..."
    helm uninstall orc8r -n orc8r 2>/dev/null || true
    helm uninstall orc8r-postgresql -n db 2>/dev/null || true
    helm uninstall orc8r-mysql -n db 2>/dev/null || true
    helm uninstall cert-manager -n cert-manager 2>/dev/null || true
    
    # Delete namespaces
    echo "🧹 Removing namespaces..."
    kubectl delete namespace orc8r 2>/dev/null || true
    kubectl delete namespace db 2>/dev/null || true
    kubectl delete namespace cert-manager 2>/dev/null || true
    
    # Remove PVCs
    echo "🧹 Removing persistent volume claims..."
    kubectl delete pvc --all -n db 2>/dev/null || true
    
    # Clean up temp directories
    echo "🧹 Removing temporary directories..."
    rm -rf "$CERTS_DIR" "$CUSTOM_CHART_DIR" 2>/dev/null || true
    
    # Clean up credentials file
    if [ -f "$CREDENTIALS_FILE" ]; then
        echo "🧹 Removing credentials file..."
        rm -f "$CREDENTIALS_FILE"
    fi
    
    echo "✅ Cleanup complete. You can now run the installation script again."
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    cleanup
}

# Run the script
main "$@" 