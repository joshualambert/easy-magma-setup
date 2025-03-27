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

# Function to check if a command succeeded
check_error() {
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: $1"
        echo "Run '$0 troubleshoot' for detailed diagnostics."
        exit 1
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

# Function to check system resources
check_resources() {
    echo "🔍 Checking system resources..."
    
    # Check CPU
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        echo "⚠️ WARNING: Only $CPU_CORES CPU core(s) detected. 2+ cores recommended."
    else
        echo "✅ CPU: $CPU_CORES cores"
    fi
    
    # Check RAM
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB/1024/1024" | bc)
    if (( $(echo "$TOTAL_RAM_GB < 3.5" | bc -l) )); then
        echo "⚠️ WARNING: Only ${TOTAL_RAM_GB}GB RAM detected. 4GB+ recommended."
    else
        echo "✅ RAM: ${TOTAL_RAM_GB}GB"
    fi
    
    # Check disk space
    DISK_FREE_KB=$(df -k . | awk 'NR==2 {print $4}')
    DISK_FREE_GB=$(echo "scale=1; $DISK_FREE_KB/1024/1024" | bc)
    if (( $(echo "$DISK_FREE_GB < 19.5" | bc -l) )); then
        echo "⚠️ WARNING: Only ${DISK_FREE_GB}GB free disk space. 20GB+ recommended."
    else
        echo "✅ Disk: ${DISK_FREE_GB}GB free"
    fi
}

# Function to install system dependencies
install_dependencies() {
    echo "🔄 Updating system and installing dependencies..."
    
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

# Function to clone Magma repository
clone_magma() {
    echo "📦 Cloning Magma repository..."
    
    if [ -d "$BASE_DIR" ]; then
        echo "📂 Magma repository directory already exists at $BASE_DIR"
        
        # Check if it's actually a git repo
        if [ -d "$BASE_DIR/.git" ]; then
            echo "✅ Valid git repository found, skipping clone."
        else
            echo "⚠️ Directory exists but is not a git repository. Backing up and cloning..."
            mv "$BASE_DIR" "${BASE_DIR}_backup_$(date +%Y%m%d%H%M%S)"
            git clone --depth 1 "$MAGMA_REPO" "$BASE_DIR"
            check_error "Failed to clone Magma repository"
        fi
    else
        git clone --depth 1 "$MAGMA_REPO" "$BASE_DIR"
        check_error "Failed to clone Magma repository"
    fi
    
    echo "✅ Magma repository setup complete!"
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
    
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    kubectl create namespace cert-manager || true
    
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
    
    echo "✅ Cert-manager setup complete!"
}

# Function to generate TLS certificates
generate_certs() {
    echo "🔏 Generating TLS certificates in $CERT_DIR..."
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR" || exit 1

    # Generate controller certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout controller.key -out controller.crt \
        -subj "/CN=${ORC8R_DOMAIN}"
    check_error "Failed to generate controller certificate"
    
    # Generate certifier certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certifier.key -out certifier.pem \
        -subj "/CN=certifier.magma.com"
    check_error "Failed to generate certifier certificate"
    
    # Generate bootstrapper key in PEM format (important for compatibility)
    echo "🔐 Generating bootstrapper key in proper format..."
    openssl genrsa -out bootstrapper.key 2048
    check_error "Failed to generate bootstrapper key"
    
    # Generate a separate root CA (don't reuse bootstrapper key)
    echo "🔐 Generating separate Root CA..."
    openssl genrsa -out rootCA.key 2048
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 365 \
        -out rootCA.pem \
        -subj "/CN=rootCA"
    check_error "Failed to generate root CA certificate"
        
    # Generate admin operator cert
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout admin_operator.key.pem -out admin_operator.pem \
        -subj "/CN=admin_operator"
    check_error "Failed to generate admin operator certificate"
    
    # Check if all required files were generated
    echo "🔍 Verifying certificate files..."
    for cert_file in controller.key controller.crt certifier.key certifier.pem bootstrapper.key rootCA.pem admin_operator.key.pem admin_operator.pem; do
        if [ ! -f "$cert_file" ]; then
            echo "❌ Certificate file $cert_file is missing"
            exit 1
        fi
    done
    
    verbose "Generated certificates with the following permissions:"
    if [ "$VERBOSE" = true ]; then
        ls -la "$CERT_DIR"
    fi
    
    echo "✅ TLS certificates generated successfully!"
}

# Function to create Kubernetes secrets
create_secrets() {
    echo "🔐 Creating Kubernetes secrets..."
    
    # Create namespaces if they don't exist
    kubectl create namespace orc8r 2>/dev/null || true
    kubectl create namespace db 2>/dev/null || true

    # Clean up existing secrets to avoid errors on re-runs
    echo "🧹 Removing any existing secrets..."
    kubectl -n orc8r delete secret orc8r-secrets-certs 2>/dev/null || true
    kubectl -n orc8r delete secret orc8r-secrets-envdir 2>/dev/null || true
    kubectl -n orc8r delete secret orc8r-secrets-configs-orc8r 2>/dev/null || true
    kubectl -n db delete secret orc8r-postgres-tls-secret 2>/dev/null || true

    # Orchestrator certs secret
    echo "🔐 Creating orchestrator certificates secret..."
    kubectl -n orc8r create secret generic orc8r-secrets-certs \
        --from-file=controller.crt=controller.crt \
        --from-file=controller.key=controller.key \
        --from-file=rootCA.pem=rootCA.pem \
        --from-file=certifier.pem=certifier.pem \
        --from-file=certifier.key=certifier.key \
        --from-file=bootstrapper.key=bootstrapper.key \
        --from-file=admin_operator.pem=admin_operator.pem \
        --from-file=admin_operator.key.pem=admin_operator.key.pem
    check_error "Failed to create orc8r-secrets-certs secret"

    # Database connection secret - With clear sslmode flag
    echo "🔐 Creating database connection secret..."
    kubectl -n orc8r create secret generic orc8r-secrets-envdir \
        --from-literal=DATABASE_SOURCE="dbname=orc8r user=orc8r password=$ORC8R_DB_PWD host=orc8r-postgres-postgresql.db sslmode=disable" \
        --from-literal=CONTROLLER_SERVICES="ACCESSD,ACTIVATIOND,AGGREGATOR,BOOTSTRAPPER,CERTIFIER,DEVICE,DISPATCHER,EVENTD,LOGS,METRICSD,OBSIDIAN,POLICYDB,SERVICE_REGISTRY,SMSSTORE,STATE,STREAMER,SUBSCRIBERDB,SWAGGER,UPGRADE,CONFIGURATION,METERINGD_RECORDS,DIRECTORYD"
    check_error "Failed to create orc8r-secrets-envdir secret"

    # PostgreSQL TLS secret with Bitnami-compatible key names
    echo "🔐 Creating PostgreSQL TLS secret..."
    kubectl -n db create secret generic orc8r-postgres-tls-secret \
        --from-file=tls.crt=controller.crt \
        --from-file=tls.key=controller.key \
        --from-file=ca.crt=rootCA.pem
    check_error "Failed to create orc8r-postgres-tls-secret"

    # Metrics config secret
    echo "🔐 Creating metrics configuration secret..."
    cat > "$METRICSD_FILE" <<EOF
profile: "prometheus"
prometheusQueryAddress: "http://orc8r-prometheus:9090"
prometheusPushAddresses:
  - "http://orc8r-prometheus-cache:9091/metrics"
alertmanagerApiURL: "http://orc8r-alertmanager:9093/api/v2/alerts"
prometheusConfigServiceURL: "http://orc8r-config-manager:9100"
alertmanagerConfigServiceURL: "http://orc8r-config-manager:9101"
EOF
    kubectl -n orc8r create secret generic orc8r-secrets-configs-orc8r \
        --from-file=metricsd.yml="$METRICSD_FILE"
    check_error "Failed to create orc8r-secrets-configs-orc8r secret"
    
    verbose "MetricsD configuration:"
    if [ "$VERBOSE" = true ]; then
        cat "$METRICSD_FILE"
    fi
    
    echo "✅ Kubernetes secrets created successfully!"
}

# Function to patch Helm charts
patch_helm_charts() {
    echo "🔧 Patching Helm charts..."
    cd "$HELM_DIR" || exit 1
    
    echo "🔧 Patching deprecated policy/v1beta1 to policy/v1..."
    if grep -q 'policy/v1beta1' ./orc8r; then
        grep -rl 'policy/v1beta1' ./orc8r | xargs sed -i 's|policy/v1beta1|policy/v1|g'
        check_error "Failed to patch policy/v1beta1 references"
    else
        echo "✅ No policy/v1beta1 references found, skipping patch"
    fi
    
    echo "✅ Helm charts patched successfully!"
}

# Function to install databases using values file for PostgreSQL
install_databases() {
    echo "🐘 Installing databases..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    # Check if PostgreSQL is already installed
    if kubectl get pods -n db -l app.kubernetes.io/name=postgresql &> /dev/null; then
        echo "⚠️ PostgreSQL appears to be already installed. Checking status..."
        POSTGRES_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
        
        if [ "$POSTGRES_POD" != "not-found" ]; then
            POD_STATUS=$(kubectl get pod "$POSTGRES_POD" -n db -o jsonpath='{.status.phase}')
            if [ "$POD_STATUS" == "Running" ]; then
                echo "✅ PostgreSQL is already running. Retrieving password..."
                # Get the actual PostgreSQL password
                ACTUAL_PG_PASSWORD=$(kubectl get secret -n db orc8r-postgres-postgresql -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)
                
                if [ -n "$ACTUAL_PG_PASSWORD" ]; then
                    echo "✅ Retrieved existing PostgreSQL password."
                    ORC8R_DB_PWD="$ACTUAL_PG_PASSWORD"
                    
                    # Update the secret with the correct password
                    echo "🔄 Updating database connection string with existing PostgreSQL password..."
                    kubectl -n orc8r create secret generic orc8r-secrets-envdir \
                        --from-literal=DATABASE_SOURCE="dbname=orc8r user=orc8r password=$ACTUAL_PG_PASSWORD host=orc8r-postgres-postgresql.db sslmode=disable" \
                        --from-literal=CONTROLLER_SERVICES="ACCESSD,ACTIVATIOND,AGGREGATOR,BOOTSTRAPPER,CERTIFIER,DEVICE,DISPATCHER,EVENTD,LOGS,METRICSD,OBSIDIAN,POLICYDB,SERVICE_REGISTRY,SMSSTORE,STATE,STREAMER,SUBSCRIBERDB,SWAGGER,UPGRADE,CONFIGURATION,METERINGD_RECORDS,DIRECTORYD" \
                        --dry-run=client -o yaml | kubectl apply -f -
                    
                    # Skip PostgreSQL installation
                    echo "🔄 Skipping PostgreSQL installation as it's already running."
                    goto_mysql=1
                else
                    echo "⚠️ Could not retrieve PostgreSQL password. Reinstalling..."
                    helm uninstall orc8r-postgres -n db
                    sleep 10
                    goto_mysql=0
                fi
            else
                echo "⚠️ PostgreSQL pod found but not running correctly. Status: $POD_STATUS"
                echo "🔄 Reinstalling PostgreSQL..."
                helm uninstall orc8r-postgres -n db
                sleep 10
                goto_mysql=0
            fi
        else
            goto_mysql=0
        fi
    else
        goto_mysql=0
    fi
    
    if [ "$goto_mysql" -eq 0 ]; then
        # Create PostgreSQL values file - Explicitly disable TLS
        echo "📝 Creating PostgreSQL values file..."
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
        check_error "Failed to install PostgreSQL"

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
        check_error "PostgreSQL pod did not reach ready state"
        
        # Verify PostgreSQL is working
        echo "🔍 Checking PostgreSQL functionality..."
        kubectl exec -it "$POSTGRES_POD" -n db -- ps aux | grep postgres
        check_error "PostgreSQL is not running correctly"
        
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
        check_error "Failed to update database connection string"
    fi
    
    # Check if MySQL is already installed
    if kubectl get pods -n db -l app.kubernetes.io/name=mysql &> /dev/null; then
        echo "⚠️ MySQL appears to be already installed. Checking status..."
        MYSQL_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
        
        if [ "$MYSQL_POD" != "not-found" ]; then
            POD_STATUS=$(kubectl get pod "$MYSQL_POD" -n db -o jsonpath='{.status.phase}')
            if [ "$POD_STATUS" == "Running" ]; then
                echo "✅ MySQL is already running. Retrieving password..."
                # Get the actual MySQL password
                ACTUAL_MYSQL_PASSWORD=$(kubectl get secret -n db nms-mysql -o jsonpath='{.data.mysql-password}' 2>/dev/null | base64 --decode)
                
                if [ -n "$ACTUAL_MYSQL_PASSWORD" ]; then
                    echo "✅ Retrieved existing MySQL password."
                    NMS_DB_PWD="$ACTUAL_MYSQL_PASSWORD"
                    echo "🔄 Skipping MySQL installation as it's already running."
                else
                    echo "⚠️ Could not retrieve MySQL password. Reinstalling..."
                    helm uninstall nms-mysql -n db
                    sleep 10
                    install_mysql=1
                fi
            else
                echo "⚠️ MySQL pod found but not running correctly. Status: $POD_STATUS"
                echo "🔄 Reinstalling MySQL..."
                helm uninstall nms-mysql -n db
                sleep 10
                install_mysql=1
            fi
        else
            install_mysql=1
        fi
    else
        install_mysql=1
    fi
    
    if [ "${install_mysql:-0}" -eq 1 ]; then
        # Install MySQL for NMS
        echo "🐬 Installing MySQL for NMS..."
        helm install nms-mysql bitnami/mysql \
            --namespace db \
            --set auth.username=nms \
            --set auth.password="$NMS_DB_PWD" \
            --set auth.database=nms \
            --wait
        check_error "Failed to install MySQL"
        
        # Wait for MySQL to be ready
        echo "⏳ Waiting for MySQL to be fully ready..."
        MYSQL_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
        if [ "$MYSQL_POD" != "not-found" ]; then
            kubectl wait --for=condition=ready pod "$MYSQL_POD" -n db --timeout=120s
            check_error "MySQL pod did not reach ready state"
        else
            echo "⚠️ MySQL pod not found after installation. Check pod status..."
            kubectl get pods -n db
        fi
        
        # Get the actual MySQL password
        ACTUAL_MYSQL_PASSWORD=$(kubectl get secret -n db nms-mysql -o jsonpath='{.data.mysql-password}' | base64 --decode)
        if [ -n "$ACTUAL_MYSQL_PASSWORD" ]; then
            NMS_DB_PWD="$ACTUAL_MYSQL_PASSWORD"
        fi
    fi
    
    # Update credentials file with the actual passwords
    update_credentials
    
    echo "✅ Databases installed and verified successfully!"
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
# Added resource limits to prevent OOM issues
controller:
  podDisruptionBudget:
    enabled: false
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 250Mi
    limits:
      cpu: 2000m
      memory: 1Gi
metrics:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 250Mi
    limits:
      cpu: 1000m
      memory: 1Gi
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
    
    # Check if orc8r is already installed
    if helm list -n orc8r 2>/dev/null | grep -q "orc8r"; then
        echo "⚠️ Orchestrator appears to be already installed. Checking status..."
        
        # Count running pods in orc8r namespace
        RUNNING_PODS=$(kubectl get pods -n orc8r --field-selector=status.phase=Running 2>/dev/null | grep -v NAME | wc -l)
        
        if [ "$RUNNING_PODS" -gt 0 ]; then
            echo "✅ Orchestrator has $RUNNING_PODS running pods. Attempting upgrade with new values..."
            
            # Update dependencies and upgrade
            helm dependency update orc8r
            helm upgrade orc8r ./orc8r -f orc8r-values.yaml --namespace orc8r --timeout 15m
            check_error "Failed to upgrade Orchestrator"
        else
            echo "⚠️ Orchestrator is installed but no pods are running. Uninstalling and reinstalling..."
            helm uninstall orc8r -n orc8r
            sleep 30
            
            # Reinstall from scratch
            helm dependency update orc8r
            helm install orc8r ./orc8r -f orc8r-values.yaml --namespace orc8r --timeout 15m
            check_error "Failed to install Orchestrator"
        fi
    else
        # Fresh installation
        helm dependency update orc8r
        helm install orc8r ./orc8r -f orc8r-values.yaml --namespace orc8r --timeout 15m
        check_error "Failed to install Orchestrator"
    fi
    
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
        ATTEMPTS=0
        MAX_ATTEMPTS=30
        
        until kubectl -n orc8r get pods -l app.kubernetes.io/component="$component" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running || [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; do
            echo "🔄 Waiting for $component pod to be running... (Attempt $(($ATTEMPTS+1))/$MAX_ATTEMPTS)"
            sleep 10
            ATTEMPTS=$((ATTEMPTS+1))
        done
        
        if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
            echo "❌ Timeout waiting for $component pod to be running"
            exit 1
        fi
        
        echo "✅ $component is running."
        
        # Wait for pod to be ready
        POD_NAME=$(kubectl -n orc8r get pods -l app.kubernetes.io/component="$component" -o jsonpath='{.items[0].metadata.name}')
        echo "⏳ Waiting for $component pod $POD_NAME to be fully ready..."
        kubectl wait --for=condition=ready pod "$POD_NAME" -n orc8r --timeout=180s
        check_error "$component pod did not reach ready state"
    done

    # Add additional wait time to ensure services are truly ready
    echo "⏳ Waiting an additional 60 seconds for services to stabilize..."
    sleep 60

    MAGMALTE_POD=$(kubectl -n orc8r get pods -l app.kubernetes.io/component=magmalte -o jsonpath='{.items[0].metadata.name}')
    echo "👤 Creating admin user in pod $MAGMALTE_POD..."
    
    ADMIN_CREATION_OUTPUT=$(kubectl -n orc8r exec -it "$MAGMALTE_POD" -- magmalte/scripts/create_admin_user.sh "$EMAIL" "$ADMIN_PASSWORD" 2>&1)
    
    if echo "$ADMIN_CREATION_OUTPUT" | grep -q "Created new admin user"; then
        echo "✅ Admin user created successfully!"
    elif echo "$ADMIN_CREATION_OUTPUT" | grep -q "User already exists"; then
        echo "✅ Admin user already exists!"
    else
        echo "⚠️ Unexpected output while creating admin user:"
        echo "$ADMIN_CREATION_OUTPUT"
        
        echo "🔄 Retrying admin user creation with additional diagnostics..."
        # Check script existence
        kubectl -n orc8r exec -it "$MAGMALTE_POD" -- ls -la magmalte/scripts/
        
        # Run with more debugging
        kubectl -n orc8r exec -it "$MAGMALTE_POD" -- env ADMIN_USER="$EMAIL" ADMIN_PASSWORD="$ADMIN_PASSWORD" magmalte/scripts/create_admin_user.sh "$EMAIL" "$ADMIN_PASSWORD"
    fi
}

# Function to display status and final details
display_status() {
    echo "🔍 Showing cluster status..."
    echo "🔍 Pods in orc8r namespace:"
    kubectl get pods -n orc8r
    
    echo "🔍 Pods in db namespace:"
    kubectl get pods -n db
    
    echo "🔍 Services in orc8r namespace:"
    kubectl get svc -n orc8r

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
        
        # Add a hosts file configuration suggestion
        echo ""
        echo "💡 You can add this to your local /etc/hosts file for testing:"
        echo "   ${SERVER_IP} ${ORC8R_DOMAIN}"
        
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
        echo "⚠️ Run '$0 troubleshoot' for detailed diagnostics."
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
    echo "🔧 Running detailed troubleshooting checks..."
    
    # Check system resources
    check_resources
    
    # Check all namespaces
    echo "🔍 Checking namespaces:"
    kubectl get namespaces
    
    # Check node status
    echo "🔍 Checking node status:"
    kubectl describe nodes
    
    # Check all resources in orc8r namespace
    echo "🔍 All resources in orc8r namespace:"
    kubectl get all -n orc8r
    
    # Check all resources in db namespace
    echo "🔍 All resources in db namespace:"
    kubectl get all -n db
    
    # Check PostgreSQL specifically
    echo "🔍 Checking PostgreSQL status:"
    POSTGRES_POD=$(kubectl get pods -n db -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    
    if [ "$POSTGRES_POD" != "not-found" ]; then
        echo "PostgreSQL pod found: $POSTGRES_POD"
        kubectl describe pod "$POSTGRES_POD" -n db | grep -A 15 "Events:"
        echo "PostgreSQL logs (last 20 lines):"
        kubectl logs "$POSTGRES_POD" -n db --tail=20
        
        # Check actual PostgreSQL password
        echo "Checking PostgreSQL secret:"
        ACTUAL_PG_PASSWORD=$(kubectl get secret -n db orc8r-postgres-postgresql -o jsonpath='{.data.password}' | base64 --decode)
        echo "Actual PostgreSQL password length: ${#ACTUAL_PG_PASSWORD} characters"
        
        # Check database connection string
        echo "Checking database connection string:"
        if kubectl get secret -n orc8r orc8r-secrets-envdir &>/dev/null; then
            DB_CONN_STRING=$(kubectl get secret -n orc8r orc8r-secrets-envdir -o jsonpath='{.data.DATABASE_SOURCE}' | base64 --decode)
            echo "Current connection string: $DB_CONN_STRING"
            
            # Check if passwords match
            if [[ "$DB_CONN_STRING" == *"$ACTUAL_PG_PASSWORD"* ]]; then
                echo "✅ Database connection password matches PostgreSQL password"
            else
                echo "❌ Database connection password does NOT match PostgreSQL password"
                echo "🔧 This is likely causing connection issues. Try running the script again."
            fi
        else
            echo "❌ Database connection secret not found in orc8r namespace"
        fi
    else
        echo "⚠️ PostgreSQL pod not found. Checking all pods in db namespace:"
        kubectl get pods -n db
    fi
    
    # Check bootstrapper pod for key format issues
    echo "🔍 Checking bootstrapper pod:"
    BOOTSTRAPPER_POD=$(kubectl get pods -n orc8r -l app.kubernetes.io/component=bootstrapper -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    if [ "$BOOTSTRAPPER_POD" != "not-found" ]; then
        echo "Bootstrapper pod found: $BOOTSTRAPPER_POD"
        kubectl describe pod "$BOOTSTRAPPER_POD" -n orc8r | grep -A 15 "Events:"
        echo "Bootstrapper logs (last 20 lines):"
        kubectl logs "$BOOTSTRAPPER_POD" -n orc8r --tail=20
    fi
    
    # Check controller pod
    echo "🔍 Checking controller pod:"
    CONTROLLER_POD=$(kubectl get pods -n orc8r -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    if [ "$CONTROLLER_POD" != "not-found" ]; then
        echo "Controller pod found: $CONTROLLER_POD"
        kubectl describe pod "$CONTROLLER_POD" -n orc8r | grep -A 15 "Events:"
        echo "Controller logs (last 20 lines):"
        kubectl logs "$CONTROLLER_POD" -n orc8r --tail=20
    fi
    
    # Check magmalte pod
    echo "🔍 Checking magmalte pod:"
    MAGMALTE_POD=$(kubectl get pods -n orc8r -l app.kubernetes.io/component=magmalte -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    if [ "$MAGMALTE_POD" != "not-found" ]; then
        echo "Magmalte pod found: $MAGMALTE_POD"
        kubectl describe pod "$MAGMALTE_POD" -n orc8r | grep -A 15 "Events:"
        echo "Magmalte logs (last 20 lines):"
        kubectl logs "$MAGMALTE_POD" -n orc8r --tail=20
    fi
    
    # Check certificate secrets
    echo "🔍 Checking certificate secrets:"
    if kubectl get secret -n orc8r orc8r-secrets-certs &>/dev/null; then
        echo "Certificate secret exists in orc8r namespace"
        kubectl describe secret -n orc8r orc8r-secrets-certs
    else
        echo "❌ Certificate secret not found in orc8r namespace"
    fi
    
    # Check for any failed Helm releases
    echo "🔍 Checking Helm releases:"
    helm list --all-namespaces
    
    echo "✅ Troubleshooting complete. See above for details."
    
    # Provide recommendations
    echo ""
    echo "🔧 Troubleshooting Recommendations:"
    echo "-----------------------------------"
    echo "1. If you see database connection issues, try running: $0 cleanup"
    echo "   Then run the installation script again."
    echo ""
    echo "2. If bootstrapper is failing, check the certificate format with:"
    echo "   cd ${CERT_DIR} && openssl rsa -in bootstrapper.key -check"
    echo ""
    echo "3. Check for resource constraints - K3s might need more CPU/memory."
    echo ""
    echo "4. For persistent issues, try a fresh install after cleanup:"
    echo "   $0 cleanup"
    echo "   sudo apt purge k3s -y"
    echo "   rm -rf ~/.kube"
    echo "   Then run the installation script again."
}

# Function to cleanup a failed installation
cleanup() {
    echo "🧹 Cleaning up failed installation..."
    
    # Delete Helm releases
    echo "🧹 Removing Helm releases..."
    helm uninstall orc8r -n orc8r 2>/dev/null || true
    helm uninstall orc8r-postgres -n db 2>/dev/null || true
    helm uninstall nms-mysql -n db 2>/dev/null || true
    helm uninstall cert-manager -n cert-manager 2>/dev/null || true
    
    # Delete namespaces
    echo "🧹 Removing namespaces..."
    kubectl delete namespace orc8r 2>/dev/null || true
    kubectl delete namespace db 2>/dev/null || true
    kubectl delete namespace cert-manager 2>/dev/null || true
    
    # Remove PVCs
    echo "🧹 Removing persistent volume claims..."
    kubectl delete pvc --all -n db 2>/dev/null || true
    
    echo "✅ Cleanup complete. You can now run the installation script again."
}

# Main execution
main() {
    echo "🚀 Starting Magma Orchestrator deployment..."
    check_args "$@"
    check_resources
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
