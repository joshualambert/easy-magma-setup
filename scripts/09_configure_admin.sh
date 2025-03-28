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
    
    # Read admin credentials
    EMAIL=$(grep "Admin Email:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    ADMIN_PASSWORD=$(grep "Admin Password:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    
    # Verify all required credentials are present
    if [ -z "$EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
        echo "❌ ERROR: Missing required credentials in credentials file"
        echo "Please ensure all required credentials are set in $CREDENTIALS_FILE"
        exit 1
    fi
    
    verbose "Read credentials:"
    verbose "  EMAIL: $EMAIL"
    verbose "  ADMIN_PASSWORD: $ADMIN_PASSWORD"
}

# Function to configure admin user
configure_admin() {
    echo "👤 Configuring admin user..."
    
    # Read credentials
    read_credentials
    
    # Wait for NMS pod to be ready
    echo "⏳ Waiting for NMS pod to be ready..."
    for i in {1..30}; do
        POD_STATUS=$(kubectl -n orc8r get pods -l app=orc8r-magmalte -o jsonpath='{.items[0].status.phase}')
        if [ "$POD_STATUS" = "Running" ]; then
            break
        fi
        echo "Waiting for NMS pod... ($i/30)"
        sleep 10
    done
    
    if [ "$POD_STATUS" != "Running" ]; then
        echo "❌ ERROR: NMS pod failed to start"
        exit 1
    fi
    
    # Wait for pod to be fully ready
    echo "⏳ Waiting for pod to be fully ready..."
    sleep 30
    
    # Get NMS pod name
    NMS_POD=$(kubectl -n orc8r get pods -l app=orc8r-magmalte -o jsonpath='{.items[0].metadata.name}')
    
    # Try different commands to create admin user
    echo "🔑 Creating admin user..."
    
    # Try yarn setAdminPassword
    kubectl -n orc8r exec $NMS_POD -- yarn setAdminPassword "$EMAIL" "$ADMIN_PASSWORD" || \
    # Try yarn run setAdminPassword
    kubectl -n orc8r exec $NMS_POD -- yarn run setAdminPassword "$EMAIL" "$ADMIN_PASSWORD" || \
    # Try yarn run adduser
    kubectl -n orc8r exec $NMS_POD -- yarn run adduser "$EMAIL" "$ADMIN_PASSWORD" || \
    {
        echo "❌ ERROR: Failed to create admin user"
        echo "Please check the NMS pod logs for more information"
        exit 1
    }
    
    echo "✅ Admin user configured successfully"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    configure_admin
}

# Run the script
main "$@" 