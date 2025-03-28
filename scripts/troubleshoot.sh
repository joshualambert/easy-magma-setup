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

# Function for troubleshooting assistance
troubleshoot() {
    echo "🔧 Running detailed troubleshooting checks..."
    
    # Check system resources
    echo "🔍 Checking system resources..."
    CPU_CORES=$(nproc)
    echo "CPU Cores: $CPU_CORES"
    
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB/1024/1024" | bc)
    echo "Total RAM: ${TOTAL_RAM_GB}GB"
    
    DISK_FREE_KB=$(df -k . | awk 'NR==2 {print $4}')
    DISK_FREE_GB=$(echo "scale=1; $DISK_FREE_KB/1024/1024" | bc)
    echo "Free Disk Space: ${DISK_FREE_GB}GB"
    
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
    POSTGRES_POD=$(kubectl get pods -n db -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
    
    if [ "$POSTGRES_POD" != "not-found" ]; then
        echo "PostgreSQL pod found: $POSTGRES_POD"
        kubectl describe pod "$POSTGRES_POD" -n db | grep -A 15 "Events:"
        echo "PostgreSQL logs (last 20 lines):"
        kubectl logs "$POSTGRES_POD" -n db --tail=20
        
        # Check actual PostgreSQL password
        echo "Checking PostgreSQL secret:"
        ACTUAL_PG_PASSWORD=$(kubectl get secret -n db orc8r-postgresql -o jsonpath='{.data.postgres-password}' | base64 --decode)
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
    
    # Check key pod logs
    for component in controller bootstrapper magmalte; do
        echo "🔍 Checking $component pod:"
        POD=$(kubectl get pods -n orc8r -l app=orc8r-$component -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "not-found")
        if [ "$POD" != "not-found" ]; then
            echo "$component pod found: $POD"
            kubectl describe pod "$POD" -n orc8r | grep -A 15 "Events:"
            echo "$component logs (last 20 lines):"
            kubectl logs "$POD" -n orc8r --tail=20 || echo "No logs available"
        else
            echo "⚠️ $component pod not found"
        fi
    done
    
    # Check certificate secrets
    echo "🔍 Checking certificate secrets:"
    if kubectl get secret -n orc8r orc8r-secrets-certs &>/dev/null; then
        echo "Certificate secret exists in orc8r namespace"
        kubectl describe secret -n orc8r orc8r-secrets-certs
    else
        echo "❌ Certificate secret not found in orc8r namespace"
    fi
    
    # Check for any Helm releases
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
    echo "   cd ${CERTS_DIR} && openssl rsa -in bootstrapper.key -check"
    echo ""
    echo "3. Check for resource constraints - K3s might need more CPU/memory."
    echo ""
    echo "4. For persistent issues, try a fresh install after cleanup:"
    echo "   $0 cleanup"
    echo "   sudo apt purge k3s -y"
    echo "   rm -rf ~/.kube"
    echo "   Then run the installation script again."
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    troubleshoot
}

# Run the script
main "$@" 