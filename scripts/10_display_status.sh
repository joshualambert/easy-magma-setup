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
    
    # Read all credentials
    ORC8R_DOMAIN=$(grep "Domain:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    EMAIL=$(grep "Admin Email:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ADMIN_PASSWORD=$(grep "Admin Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ORC8R_DB_PASSWORD=$(grep "Orchestrator DB Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    NMS_MYSQL_PASSWORD=$(grep "NMS MySQL Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    
    # Verify all required credentials are present
    if [ -z "$ORC8R_DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$ADMIN_PASSWORD" ] || \
       [ -z "$ORC8R_DB_PASSWORD" ] || [ -z "$NMS_MYSQL_PASSWORD" ]; then
        echo "❌ ERROR: Missing required credentials in credentials file"
        echo "Please ensure all required credentials are set in $CREDENTIALS_FILE"
        exit 1
    fi
    
    verbose "Read credentials:"
    verbose "  ORC8R_DOMAIN: $ORC8R_DOMAIN"
    verbose "  EMAIL: $EMAIL"
    verbose "  ADMIN_PASSWORD: $ADMIN_PASSWORD"
    verbose "  ORC8R_DB_PASSWORD: $ORC8R_DB_PASSWORD"
    verbose "  NMS_MYSQL_PASSWORD: $NMS_MYSQL_PASSWORD"
}

# Function to display status and connection info
display_status() {
    echo "📊 Checking installation status..."
    
    # Read credentials
    read_credentials
    
    # Check if orc8r namespace exists
    if ! kubectl get namespace orc8r &>/dev/null; then
        echo "⚠️  orc8r namespace not found"
        echo "This is normal if you haven't completed the installation yet."
        echo "Please continue with the installation steps in order."
        echo -e "\n🔗 Access Information (will be available after installation):"
        echo "NMS URL: https://$ORC8R_DOMAIN"
        echo "IP Access: https://<server-ip>:31080"
        echo -e "\n👤 Admin Credentials:"
        echo "Email: $EMAIL"
        echo "Password: $ADMIN_PASSWORD"
        return 0
    fi
    
    # Display pod status
    echo -e "\n📋 Pod Status:"
    kubectl get pods -n orc8r
    
    # Get NodePort for NMS service
    NMS_NODEPORT=$(kubectl get svc orc8r-nms-nginx -n orc8r -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "31080")
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    # Display access information
    echo -e "\n🔗 Access Information:"
    echo "NMS URL: https://$ORC8R_DOMAIN"
    echo "IP Access: https://$SERVER_IP:$NMS_NODEPORT"
    echo -e "\n👤 Admin Credentials:"
    echo "Email: $EMAIL"
    echo "Password: $ADMIN_PASSWORD"
    
    # Update credentials file with access info
    echo -e "\n📝 Access Information (saved to $CREDENTIALS_FILE):" >> "$CREDENTIALS_FILE"
    echo "NMS URL: https://$ORC8R_DOMAIN" >> "$CREDENTIALS_FILE"
    echo "IP Access: https://$SERVER_IP:$NMS_NODEPORT" >> "$CREDENTIALS_FILE"
    echo "Last Updated: $(date)" >> "$CREDENTIALS_FILE"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    display_status
}

# Run the script
main "$@" 