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

# Function to read credentials from file
read_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "❌ ERROR: Credentials file not found at $CREDENTIALS_FILE"
        echo "Please run the main script and set credentials first (option 1)"
        exit 1
    fi
    
    # Read database passwords
    ORC8R_DB_PWD=$(grep "Orchestrator DB Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    NMS_DB_PWD=$(grep "NMS MySQL Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    
    # Verify all required credentials are present
    if [ -z "$ORC8R_DB_PWD" ] || [ -z "$NMS_DB_PWD" ]; then
        echo "❌ ERROR: Missing required database credentials in credentials file"
        echo "Please ensure all required credentials are set in $CREDENTIALS_FILE"
        exit 1
    fi
    
    verbose "Read database credentials:"
    verbose "  ORC8R_DB_PWD: $ORC8R_DB_PWD"
    verbose "  NMS_DB_PWD: $NMS_DB_PWD"
}

# Function to install databases
install_databases() {
    echo "🐘 Installing databases..."
    
    # Read credentials
    read_credentials
    
    # Create namespaces if they don't exist
    if ! kubectl get namespace db >/dev/null 2>&1; then
        echo "📁 Creating db namespace..."
        kubectl create namespace db
    fi
    
    # Install PostgreSQL
    echo "🐘 Installing PostgreSQL..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    helm install orc8r-postgresql bitnami/postgresql \
        --namespace db \
        --set auth.postgresPassword="$ORC8R_DB_PWD" \
        --set auth.database=orc8r \
        --set primary.persistence.size=10Gi \
        --set readReplicas.persistence.size=10Gi
    
    # Wait for PostgreSQL to be ready
    echo "⏳ Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n db --timeout=300s
    
    # Install MySQL
    echo "🐘 Installing MySQL..."
    helm install orc8r-mysql bitnami/mysql \
        --namespace db \
        --set auth.rootPassword="$NMS_DB_PWD" \
        --set auth.database=magma_nms \
        --set primary.persistence.size=10Gi \
        --set secondary.persistence.size=10Gi
    
    # Wait for MySQL to be ready
    echo "⏳ Waiting for MySQL to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mysql -n db --timeout=300s
    
    # Verify installations
    echo "🔍 Verifying database installations..."
    
    # Check PostgreSQL
    if ! kubectl get pod -l app.kubernetes.io/name=postgresql -n db >/dev/null 2>&1; then
        echo "❌ ERROR: PostgreSQL installation failed"
        exit 1
    fi
    
    # Check MySQL
    if ! kubectl get pod -l app.kubernetes.io/name=mysql -n db >/dev/null 2>&1; then
        echo "❌ ERROR: MySQL installation failed"
        exit 1
    fi
    
    echo "✅ Databases installed successfully"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    install_databases
}

# Run the script
main "$@" 