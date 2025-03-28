#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Constants
CERTS_DIR="/tmp/magma_certs"

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

# Function to read credentials from file
read_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "❌ ERROR: Credentials file not found at $CREDENTIALS_FILE"
        echo "Please run the main script and set credentials first (option 1)"
        exit 1
    fi
    
    # Read all required credentials
    ORC8R_DOMAIN=$(grep "Domain:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    EMAIL=$(grep "Admin Email:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ADMIN_PASSWORD=$(grep "Admin Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ORC8R_DB_PWD=$(grep "Orchestrator DB Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    NMS_DB_PWD=$(grep "NMS MySQL Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    
    # Verify all required credentials are present
    if [ -z "$ORC8R_DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$ADMIN_PASSWORD" ] || \
       [ -z "$ORC8R_DB_PWD" ] || [ -z "$NMS_DB_PWD" ]; then
        echo "❌ ERROR: Missing required credentials in credentials file"
        echo "Please ensure all required credentials are set in $CREDENTIALS_FILE"
        exit 1
    fi
    
    verbose "Read credentials:"
    verbose "  ORC8R_DOMAIN: $ORC8R_DOMAIN"
    verbose "  EMAIL: $EMAIL"
    verbose "  ADMIN_PASSWORD: $ADMIN_PASSWORD"
    verbose "  ORC8R_DB_PWD: $ORC8R_DB_PWD"
    verbose "  NMS_DB_PWD: $NMS_DB_PWD"
}

# Function to create Kubernetes secrets
create_secrets() {
    echo "🔐 Creating Kubernetes secrets..."
    
    # Read credentials
    read_credentials
    
    # Create secrets namespace if it doesn't exist
    if ! kubectl get namespace secrets >/dev/null 2>&1; then
        echo "📁 Creating secrets namespace..."
        kubectl create namespace secrets
    fi
    
    # Create secrets
    echo "🔐 Creating secrets..."
    
    # Create orchestrator secrets
    kubectl create secret generic orc8r-secrets \
        --from-literal=admin-password="$ADMIN_PASSWORD" \
        --from-literal=admin-email="$EMAIL" \
        --from-literal=db-password="$ORC8R_DB_PWD" \
        --from-literal=nms-db-password="$NMS_DB_PWD" \
        --namespace secrets
    
    # Create cert secrets
    if [ ! -d "$CERTS_DIR" ]; then
        echo "❌ ERROR: Certificates directory not found at $CERTS_DIR"
        echo "Please run certificate generation first (option 5)"
        exit 1
    fi
    
    # Create cert secrets
    kubectl create secret generic orc8r-certs \
        --from-file=rootCA.pem="$CERTS_DIR/rootCA.pem" \
        --from-file=controller.crt="$CERTS_DIR/controller.crt" \
        --from-file=controller.key="$CERTS_DIR/controller.key" \
        --from-file=certifier.pem="$CERTS_DIR/certifier.pem" \
        --from-file=certifier.key="$CERTS_DIR/certifier.key" \
        --from-file=bootstrapper.key="$CERTS_DIR/bootstrapper.key" \
        --from-file=admin_operator.pem="$CERTS_DIR/admin_operator.pem" \
        --from-file=admin_operator.key.pem="$CERTS_DIR/admin_operator.key.pem" \
        --namespace secrets
    
    # Verify secrets were created
    echo "🔍 Verifying secrets..."
    if ! kubectl get secret orc8r-secrets -n secrets >/dev/null 2>&1; then
        echo "❌ ERROR: Failed to create orc8r-secrets"
        exit 1
    fi
    
    if ! kubectl get secret orc8r-certs -n secrets >/dev/null 2>&1; then
        echo "❌ ERROR: Failed to create orc8r-certs"
        exit 1
    fi
    
    echo "✅ Secrets created successfully"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    create_secrets
}

# Run the script
main "$@" 