#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Constants
MAGMA_VERSION="v1.8.0"
WORK_DIR="/tmp/magma-installer"
REPO_DIR="$WORK_DIR/magma-repo"

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
    
    # Read credentials
    ORC8R_DOMAIN=$(grep "Domain:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    EMAIL=$(grep "Admin Email:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    NMS_DB_PWD=$(grep "NMS MySQL Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ORC8R_DB_PWD=$(grep "Orchestrator DB Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    
    # Verify required credentials
    if [ -z "$ORC8R_DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$NMS_DB_PWD" ] || [ -z "$ORC8R_DB_PWD" ]; then
        echo "❌ ERROR: Missing required credentials"
        exit 1
    fi
    
    verbose "Using domain: $ORC8R_DOMAIN"
    verbose "Database passwords retrieved successfully"
}

# Function to install Magma chart
install_chart() {
    echo "📊 Installing Magma chart..."
    
    # Read credentials first
    read_credentials
    
    # Create orc8r namespace if needed
    if ! kubectl get namespace orc8r &>/dev/null; then
        echo "📁 Creating orc8r namespace..."
        kubectl create namespace orc8r
        check_error "Failed to create namespace"
    fi
    
    # Create values file
    echo "📝 Creating values file..."
    VALUES_FILE="$WORK_DIR/orc8r-values.yaml"
    cat > "$VALUES_FILE" <<EOF
imagePullSecrets: []

secrets:
  create: false

nginx:
  service:
    type: NodePort
    ports:
      http:
        nodePort: 30080
      https:
        nodePort: 30443

controller:
  podDisruptionBudget:
    enabled: false
  replicas: 1
  spec:
    database:
      driver: postgres
      sql_dialect: psql
      db: orc8r
      host: orc8r-postgresql.db.svc.cluster.local
      port: 5432
      user: postgres
      pass: ${ORC8R_DB_PWD}

nms:
  enabled: true
  nginx:
    service:
      type: NodePort
      port: 80
      nodePort: 31080
  magmalte:
    env:
      api_host: ${ORC8R_DOMAIN}
      mysql_host: orc8r-mysql.db.svc.cluster.local
      mysql_user: root
      mysql_pass: ${NMS_DB_PWD}
      mysql_db: magma_nms
EOF
    
    # Install chart
    echo "📦 Installing Magma Orchestrator chart..."
    
    # Add Helm charts repo
    echo "📊 Adding Magma Helm repository..."
    helm repo add magma https://magma.github.io/magma/charts/ || true
    helm repo update
    check_error "Failed to update Helm repositories"
    
    # Install the chart
    echo "📊 Installing Magma Orchestrator chart..."
    helm upgrade --install orc8r magma/orc8r --namespace orc8r \
        --version "${MAGMA_VERSION#v}" \
        -f "$VALUES_FILE"
    check_error "Chart installation failed"
    
    # Wait for pods to stabilize
    echo "⏳ Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n orc8r --timeout=300s || true
    
    echo "✅ Magma Orchestrator chart installed successfully"
    kubectl get pods -n orc8r
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    install_chart
}

# Run the script
main "$@"