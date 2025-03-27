#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Constants
MAGMA_REPO="https://github.com/magma/magma.git"
BASE_DIR="$(pwd)/magma"
CERT_DIR="${BASE_DIR}/orc8r/tools/helm"
HELM_DIR="${BASE_DIR}/orc8r/cloud/helm"
METRICSD_FILE="/tmp/metricsd.yml"
POSTGRES_VALUES_FILE="/tmp/postgres-values.yaml"
CREDENTIALS_FILE="$(pwd)/magma-credentials.txt"

# Variables
ORC8R_DOMAIN=""
EMAIL=""
ORC8R_DB_PWD=""
NMS_DB_PWD=""
ADMIN_PASSWORD=""

# Function to enable verbose mode
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\n🔍 VERBOSE: $1"
    fi
}

# Function to check arguments
check_args() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 <ORC8R_DOMAIN> <EMAIL> [--verbose]"
        exit 1
    fi
    
    ORC8R_DOMAIN="$1"
    EMAIL="$2"
    
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    # Generate passwords upfront
    ORC8R_DB_PWD=$(openssl rand -hex 12)
    NMS_DB_PWD=$(openssl rand -hex 12)
    ADMIN_PASSWORD=$(openssl rand -hex 12)
    
    # Save credentials to file immediately
    echo "Saving initial credentials to $CREDENTIALS_FILE..."
    cat > "$CREDENTIALS_FILE" <<EOF
Magma Orchestrator Credentials
==============================
Domain: ${ORC8R_DOMAIN}
Admin Email: ${EMAIL}
Admin Password: ${ADMIN_PASSWORD}
Orchestrator DB Password: ${ORC8R_DB_PWD}
NMS MySQL Password: ${NMS_DB_PWD}

Generated: $(date)
EOF
    chmod 600 "$CREDENTIALS_FILE"
    
    verbose "Created credentials file: $CREDENTIALS_FILE"
    if [ "$VERBOSE" = true ]; then
        echo "----------------------------------------"
        cat "$CREDENTIALS_FILE"
        echo "----------------------------------------"
    fi
}

# Function to install system dependencies
install_dependencies() {
    echo "🔄 Updating system and installing K3s..."
    sudo apt update && sudo apt upgrade -y
    curl -sfL https://get.k3s.io | sh -

    echo "🔧 Configuring kubectl..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown "$USER":"$USER" ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG="$HOME/.kube/config"

    if ! grep -q "export KUBECONFIG=$HOME/.kube/config" ~/.bashrc; then
        echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
    fi

    echo "⚓ Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    echo "✅ System dependencies installed successfully!"
}

# Function to clone Magma repository
clone_magma() {
    echo "📦 Cloning Magma repository..."
    git clone --depth 1 "$MAGMA_REPO" "$BASE_DIR"
    echo "✅ Magma repository cloned successfully!"
}

# Function to setup cert-manager
setup_cert_manager() {
    echo "🔒 Setting up cert-manager..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    kubectl create namespace cert-manager || true
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.5.3 \
        --set installCRDs=true \
        --wait
    
    echo "✅ Cert-manager setup complete!"
}

# Function to generate TLS certificates
generate_certs() {
    echo "🔏 Generating TLS certificates in $CERT_DIR..."
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR" || exit 1

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout controller.key -out controller.crt \
        -subj "/CN=${ORC8R_DOMAIN}"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certifier.key -out certifier.pem \
        -subj "/CN=certifier.magma.com"
    
    # Use openssl genrsa for bootstrapper key (correct format)
    openssl genrsa -out bootstrapper.key 2048
    
    # Generate the rootCA.pem from bootstrapper key
    openssl req -x509 -new -nodes -key bootstrapper.key -sha256 -days 365 \
        -out rootCA.pem \
        -subj "/CN=rootCA"
        
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout admin_operator.key.pem -out admin_operator.pem \
        -subj "/CN=admin_operator"
    
    verbose "Generated certificates with the following permissions:"
    if [ "$VERBOSE" = true ]; then
        ls -la "$CERT_DIR"
    fi
    
    echo "✅ TLS certificates generated successfully!"
}

# Function to create Kubernetes secrets
create_secrets() {
    echo "🔐 Creating Kubernetes secrets..."
    kubectl create namespace orc8r || true
    kubectl create namespace db || true

    # Orchestrator certs secret
    kubectl -n orc8r create secret generic orc8r-secrets-certs \
        --from-file=controller.crt=controller.crt \
        --from-file=controller.key=controller.key \
        --from-file=rootCA.pem=rootCA.pem \
        --from-file=certifier.pem=certifier.pem \
        --from-file=certifier.key=certifier.key \
        --from-file=bootstrapper.key=bootstrapper.key \
        --from-file=admin_operator.pem=admin_operator.pem \
        --from-file=admin_operator.key.pem=admin_operator.key.pem || true

    # Database connection secret - Using sslmode=disable for reliability
    kubectl -n orc8r create secret generic orc8r-secrets-envdir \
        --from-literal=DATABASE_SOURCE="dbname=orc8r user=orc8r password=$ORC8R_DB_PWD host=orc8r-postgres-postgresql.db sslmode=disable" \
        --from-literal=CONTROLLER_SERVICES="ACCESSD,ACTIVATIOND,AGGREGATOR,BOOTSTRAPPER,CERTIFIER,DEVICE,DISPATCHER,EVENTD,LOGS,METRICSD,OBSIDIAN,POLICYDB,SERVICE_REGISTRY,SMSSTORE,STATE,STREAMER,SUBSCRIBERDB,SWAGGER,UPGRADE,CONFIGURATION,METERINGD_RECORDS,DIRECTORYD" || true

    # PostgreSQL TLS secret with Bitnami-compatible key names
    kubectl -n db create secret generic orc8r-postgres-tls-secret \
        --from-file=tls.crt=controller.crt \
        --from-file=tls.key=controller.key \
        --from-file=ca.crt=rootCA.pem || true

    # Metrics config secret
    cat > "$METRICSD_FILE" <<EOF
profile: "prometheus"
prometheusQueryAddress: "http://orc8r-prometheus:9090"
prometheusPushAddresses:
  - "http://orc8r-prometheus-cache:9091/metrics"
alertmanagerApiURL: "http://orc8r-alertmanager:9093/api/v2/alerts"
prometheusConfigServiceURL: "http://orc8r-config-manager:9100"
alertmanagerConfigServiceURL: "http://orc8r-config-manager:9101"
EOF
    kubectl delete secret orc8r-secrets-configs -n orc8r 2>/dev/null || true
    kubectl -n orc8r create secret generic orc8r-secrets-configs-orc8r \
        --from-file=metricsd.yml="$METRICSD_FILE" || true
    
    verbose "MetricsD configuration:"
    if [ "$VERBOSE" = true ]; then
        cat "$METRICSD_FILE"
    fi
    
    echo "✅ Kubernetes secrets created successfully!"
}

# Function to patch Helm charts
patch_helm_charts() {
    echo "🔧 Patching deprecated policy/v1beta1 to policy/v1..."
    cd "$HELM_DIR" || exit 1
    grep -rl 'policy/v1beta1' ./orc8r | xargs sed -i 's|policy/v1beta1|policy/v1|g'
    
    echo "✅ Helm charts patched successfully!"
}

# Function to install databases using values file for PostgreSQL
install_databases() {
    echo "🐘 Installing databases..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    # Create PostgreSQL values file - Using simplified config without SSL
    cat > "$POSTGRES_VALUES_FILE" <<EOF
auth:
  username: orc8r
  password: "$ORC8R_DB_PWD"
  database: orc8r

# Explicitly disable TLS to avoid certificate issues
tls:
  enabled: false

# Explicitly disable SSL in PostgreSQL
primary:
  extraFlags:
    - "-c"
    - "ssl=off"
EOF

    verbose "PostgreSQL values file:"
    if [ "$VERBOSE" = true ]; then
        cat "$POSTGRES_VALUES_FILE"
    fi

    # Install PostgreSQL with values file
    echo "🐘 Installing PostgreSQL..."
    helm install orc8r-postgres bitnami/postgresql \
        --namespace db \
        --values "$POSTGRES_VALUES_FILE" \
        --wait

    # Verify PostgreSQL is running correctly
    echo "🔍 Verifying PostgreSQL deployment..."
    POSTGRES_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    
    if [ "$POSTGRES_POD" == "not-found" ]; then
        echo "❌ PostgreSQL pod not found. Checking pod status..."
        kubectl get pods -n db
        exit 1
    fi
    
    # Wait for PostgreSQL to be ready
    echo "⏳ Waiting for PostgreSQL to be fully ready..."
    kubectl wait --for=condition=ready pod "$POSTGRES_POD" -n db --timeout=120s
    
    # Update the secret with the correct PostgreSQL password
    echo "🔄 Updating database connection string with verified PostgreSQL credentials..."
    ACTUAL_PG_PASSWORD=$(kubectl get secret -n db orc8r-postgres-postgresql -o jsonpath='{.data.password}' | base64 --decode)
    
    # Update the global variable to ensure consistency
    ORC8R_DB_PWD="$ACTUAL_PG_PASSWORD"
    
    # Update connection string with verified password
    kubectl create secret generic orc8r-secrets-envdir -n orc8r \
      --from-literal=DATABASE_SOURCE="dbname=orc8r user=orc8r password=$ACTUAL_PG_PASSWORD host=orc8r-postgres-postgresql.db sslmode=disable" \
      --from-literal=CONTROLLER_SERVICES="ACCESSD,ACTIVATIOND,AGGREGATOR,BOOTSTRAPPER,CERTIFIER,DEVICE,DISPATCHER,EVENTD,LOGS,METRICSD,OBSIDIAN,POLICYDB,SERVICE_REGISTRY,SMSSTORE,STATE,STREAMER,SUBSCRIBERDB,SWAGGER,UPGRADE,CONFIGURATION,METERINGD_RECORDS,DIRECTORYD" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    # Install MySQL for NMS
    echo "🐬 Installing MySQL for NMS..."
    helm install nms-mysql bitnami/mysql \
        --namespace db \
        --set auth.username=nms \
        --set auth.password="$NMS_DB_PWD" \
        --set auth.database=nms \
        --wait
    
    # Update credentials file with the actual PostgreSQL password
    update_credentials
    
    echo "✅ Databases installed successfully!"
}

# Function to create Helm values file
create_helm_values() {
    echo "⚙️ Creating Helm values file..."
    cd "$HELM_DIR" || exit 1
    cat <<EOF > orc8r-values.yaml
domain: ${ORC8R_DOMAIN}
proxy:
  controller:
    service:
      type: NodePort
nginx:
  spec:
    hostname: ${ORC8R_DOMAIN}
nms:
  magmalte:
    manifests:
      secrets: true
    env:
      api_host: ${ORC8R_DOMAIN}
      mysql_host: nms-mysql.db.svc.cluster.local
      mysql_db: nms
      mysql_user: nms
      mysql_pass: $NMS_DB_PWD
  nginx:
    env:
      NMS_USE_SSL: false
    image:
      repository: bitnami/nginx
      tag: 1.25.3-debian-11-r13
      pullPolicy: IfNotPresent
secrets:
  create: false
  certs: orc8r-secrets-certs
  envdir: orc8r-secrets-envdir
  configs: orc8r-secrets-configs-orc8r
EOF

    verbose "Helm values file:"
    if [ "$VERBOSE" = true ]; then
        cat orc8r-values.yaml
    fi
    
    echo "✅ Helm values file created successfully!"
}

# Function to install Orchestrator
install_orchestrator() {
    echo "🚀 Installing Magma Orchestrator..."
    cd "$HELM_DIR" || exit 1
    helm dependency update orc8r
    helm install orc8r ./orc8r -f orc8r-values.yaml --namespace orc8r --create-namespace --wait --timeout 15m
    
    echo "✅ Magma Orchestrator installed successfully!"
}

# Function to configure admin user
configure_admin() {
    echo "👤 Configuring admin user..."
    echo "⏳ Waiting for Orchestrator core pods to be ready..."
    # Wait for critical pods to be ready before configuring admin user
    REQUIRED_COMPONENTS=(magmalte nginx-proxy)

    for component in "${REQUIRED_COMPONENTS[@]}"; do
        echo "🔍 Checking for $component pod..."
        until kubectl -n orc8r get pods -l app.kubernetes.io/component="$component" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
            echo "🔄 Waiting for $component pod to be running..."
            sleep 10
        done
        echo "✅ $component is ready."
    done

    # Add additional wait time to ensure services are truly ready
    echo "⏳ Waiting an additional 30 seconds for services to stabilize..."
    sleep 30

    MAGMALTE_POD=$(kubectl -n orc8r get pods -l app.kubernetes.io/component=magmalte -o jsonpath='{.items[0].metadata.name}')
    echo "👤 Creating admin user in pod $MAGMALTE_POD..."
    kubectl -n orc8r exec -it "$MAGMALTE_POD" -- \
        magmalte/scripts/create_admin_user.sh "$EMAIL" "$ADMIN_PASSWORD"
    
    echo "✅ Admin user configured successfully!"
}

# Function to display status and final details
display_status() {
    echo "🔍 Showing cluster status..."
    kubectl get pods -A
    kubectl get svc -A

    NMS_SERVICE=$(kubectl get svc -n orc8r -l app.kubernetes.io/component=nginx-proxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    if [ "$NMS_SERVICE" != "not-found" ]; then
        NMS_PORT=$(kubectl get svc "$NMS_SERVICE" -n orc8r -o jsonpath='{.spec.ports[0].nodePort}')
        SERVER_IP=$(hostname -I | awk '{print $1}')
        
        echo ""
        echo "✅ Magma Orchestrator + NMS deployed successfully!"
        echo "==============================================="
        echo "🌐 Access NMS at: http://${ORC8R_DOMAIN}:${NMS_PORT}"
        echo "🌐 Or using IP: http://${SERVER_IP}:${NMS_PORT}"
        echo ""
        echo "👤 Admin Email: ${EMAIL}"
        echo "🔑 Admin Password: ${ADMIN_PASSWORD}"
        echo "🐘 Orchestrator DB Password: ${ORC8R_DB_PWD}"
        echo "🐬 NMS MySQL Password: ${NMS_DB_PWD}"
        echo ""
        echo "📝 All credentials saved to: $CREDENTIALS_FILE"
        echo ""
        echo "⚠️ Important: You may need to configure your DNS or /etc/hosts file to point ${ORC8R_DOMAIN} to your server's IP address."
        echo "⚠️ You'll also need to ensure any firewalls allow access to port ${NMS_PORT}."
        
        # Update credentials file with access info
        cat >> "$CREDENTIALS_FILE" <<EOF

Access Information (Updated: $(date))
===============================================
NMS URL: http://${ORC8R_DOMAIN}:${NMS_PORT}
IP Access: http://${SERVER_IP}:${NMS_PORT}
EOF
    else
        echo "⚠️ NMS service not found. Partial deployment detected."
        echo "⚠️ Check pod status and logs for errors."
    fi
}

# Function to check pod status
check_pod_status() {
    echo "🔍 Checking pod status..."
    
    # Check orc8r namespace
    echo "🔍 Pods in orc8r namespace:"
    kubectl get pods -n orc8r
    
    # Check db namespace
    echo "🔍 Pods in db namespace:"
    kubectl get pods -n db
    
    # If verbose, show more details
    if [ "$VERBOSE" = true ]; then
        echo "🔍 Detailed pod information:"
        kubectl describe pods -n orc8r | grep -A 10 "Events:"
        kubectl describe pods -n db | grep -A 10 "Events:"
    fi
}

# Function to save credentials to a file
update_credentials() {
    echo "💾 Updating credentials in $CREDENTIALS_FILE..."
    
    # Get NMS access information
    NMS_SERVICE=$(kubectl get svc -n orc8r -l app.kubernetes.io/component=nginx-proxy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    NMS_PORT=""
    if [ "$NMS_SERVICE" != "not-found" ]; then
        NMS_PORT=$(kubectl get svc "$NMS_SERVICE" -n orc8r -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "not-found")
    fi
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    cat > "$CREDENTIALS_FILE" <<EOF
Magma Orchestrator Credentials
==============================
Domain: ${ORC8R_DOMAIN}
Admin Email: ${EMAIL}
Admin Password: ${ADMIN_PASSWORD}
Orchestrator DB Password: ${ORC8R_DB_PWD}
NMS MySQL Password: ${NMS_DB_PWD}

Generated: $(date)
EOF
    
    if [ "$NMS_PORT" != "" ] && [ "$NMS_PORT" != "not-found" ]; then
        cat >> "$CREDENTIALS_FILE" <<EOF

Access Information (Updated: $(date))
===============================================
NMS URL: http://${ORC8R_DOMAIN}:${NMS_PORT}
IP Access: http://${SERVER_IP}:${NMS_PORT}
EOF
    fi
    
    chmod 600 "$CREDENTIALS_FILE"
    echo "✅ Credentials updated in: $CREDENTIALS_FILE"
}

# Function for troubleshooting assistance
troubleshoot() {
    echo "🔧 Running troubleshooting checks..."
    
    # Check all namespaces
    echo "🔍 Checking namespaces:"
    kubectl get namespaces
    
    # Check PostgreSQL specifically
    echo "🔍 Checking PostgreSQL status:"
    POSTGRES_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    
    if [ "$POSTGRES_POD" != "not-found" ]; then
        echo "PostgreSQL pod found: $POSTGRES_POD"
        kubectl describe pod "$POSTGRES_POD" -n db
        echo "PostgreSQL logs:"
        kubectl logs "$POSTGRES_POD" -n db
        
        # Check actual PostgreSQL password
        echo "Checking PostgreSQL secret:"
        ACTUAL_PG_PASSWORD=$(kubectl get secret -n db orc8r-postgres-postgresql -o jsonpath='{.data.password}' | base64 --decode)
        echo "Actual PostgreSQL password: $ACTUAL_PG_PASSWORD"
        
        # Check database connection string
        echo "Checking database connection string:"
        DB_CONN_STRING=$(kubectl get secret -n orc8r orc8r-secrets-envdir -o jsonpath='{.data.DATABASE_SOURCE}' | base64 --decode)
        echo "Current connection string: $DB_CONN_STRING"
    else
        echo "⚠️ PostgreSQL pod not found. Checking all pods in db namespace:"
        kubectl get pods -n db
    fi
    
    # Check bootstrapper pod for key format issues
    echo "🔍 Checking bootstrapper pod:"
    BOOTSTRAPPER_POD=$(kubectl get pods -n orc8r -l app.kubernetes.io/component=bootstrapper -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    if [ "$BOOTSTRAPPER_POD" != "not-found" ]; then
        echo "Bootstrapper pod found: $BOOTSTRAPPER_POD"
        kubectl logs "$BOOTSTRAPPER_POD" -n orc8r
    fi
    
    # Check for any failed Helm releases
    echo "🔍 Checking Helm releases:"
    helm list --all-namespaces
    
    echo "✅ Troubleshooting complete. See above for details."
}

# Function to cleanup a failed installation
cleanup() {
    echo "🧹 Cleaning up failed installation..."
    
    # Delete Helm releases
    helm uninstall orc8r -n orc8r 2>/dev/null || true
    helm uninstall orc8r-postgres -n db 2>/dev/null || true
    helm uninstall nms-mysql -n db 2>/dev/null || true
    
    # Delete namespaces
    kubectl delete namespace orc8r 2>/dev/null || true
    kubectl delete namespace db 2>/dev/null || true
    
    echo "✅ Cleanup complete. You can now run the installation script again."
}

# Main execution
main() {
    echo "🚀 Starting Magma Orchestrator deployment..."
    check_args "$@"
    install_dependencies
    clone_magma
    setup_cert_manager
    export HELM_EXPERIMENTAL_OCI=1
    generate_certs
    create_secrets
    patch_helm_charts
    install_databases
    create_helm_values
    
    echo "⚠️ About to install Orchestrator. This may take 15+ minutes."
    read -p "Press Enter to continue or Ctrl+C to stop here..."
    
    install_orchestrator
    configure_admin
    display_status
    update_credentials
    
    echo "🎉 Magma Orchestrator deployment complete!"
}

# If called with 'troubleshoot' argument, run troubleshooting
if [ "$1" == "troubleshoot" ]; then
    troubleshoot
    exit 0
fi

# If called with 'cleanup' argument, cleanup failed installation
if [ "$1" == "cleanup" ]; then
    cleanup
    exit 0
fi

# Run the script
main "$@"
