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
    
    # Read domain from credentials file
    ORC8R_DOMAIN=$(grep "Domain:" "$CREDENTIALS_FILE" | cut -d':' -f2 | tr -d ' ')
    if [ -z "$ORC8R_DOMAIN" ]; then
        echo "❌ ERROR: Could not find ORC8R_DOMAIN in credentials file"
        exit 1
    fi
    
    verbose "Read ORC8R_DOMAIN: $ORC8R_DOMAIN"
}

# Function to generate TLS certificates
generate_certificates() {
    echo "🔏 Generating TLS certificates..."
    
    # Read credentials
    read_credentials
    
    # Check if CERTS_DIR is set
    if [ -z "$CERTS_DIR" ]; then
        echo "❌ ERROR: CERTS_DIR environment variable is not set."
        exit 1
    fi
    
    verbose "Using CERTS_DIR: $CERTS_DIR"
    
    # Create certificates directory
    echo "📁 Creating certificates directory at $CERTS_DIR..."
    mkdir -p "$CERTS_DIR"
    cd "$CERTS_DIR" || exit 1
    
    # Generate root CA
    echo "🔏 Generating root CA..."
    openssl genrsa -out rootCA.key 2048
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.pem \
        -subj "/C=US/ST=CA/L=San Francisco/O=Magma/CN=magma.local"
    
    # Generate controller certificate
    echo "🔏 Generating controller certificate..."
    openssl genrsa -out controller.key 2048
    openssl req -new -key controller.key -out controller.csr \
        -subj "/C=US/ST=CA/L=San Francisco/O=Magma/CN=${ORC8R_DOMAIN}"
    openssl x509 -req -in controller.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
        -out controller.crt -days 3650 -sha256
    
    # Generate certifier certificate
    echo "🔏 Generating certifier certificate..."
    openssl genrsa -out certifier.key 2048
    openssl req -new -key certifier.key -out certifier.csr \
        -subj "/C=US/ST=CA/L=San Francisco/O=Magma/CN=certifier.${ORC8R_DOMAIN}"
    openssl x509 -req -in certifier.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
        -out certifier.pem -days 3650 -sha256
    
    # Generate bootstrapper key
    echo "🔏 Generating bootstrapper key..."
    openssl genrsa -out bootstrapper.key 2048
    
    # Generate admin operator certificate
    echo "🔏 Generating admin operator certificate..."
    openssl genrsa -out admin_operator.key.pem 2048
    openssl req -new -key admin_operator.key.pem -out admin_operator.csr \
        -subj "/C=US/ST=CA/L=San Francisco/O=Magma/CN=admin.${ORC8R_DOMAIN}"
    openssl x509 -req -in admin_operator.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
        -out admin_operator.pem -days 3650 -sha256
    
    # Clean up temporary files
    rm -f *.csr *.srl
    
    # Verify certificates were created
    echo "🔍 Verifying certificates..."
    for cert in rootCA.pem controller.crt certifier.pem admin_operator.pem; do
        if [ ! -f "$cert" ]; then
            echo "❌ ERROR: Failed to generate $cert"
            exit 1
        fi
    done
    
    echo "✅ Certificates generated successfully in $CERTS_DIR"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    generate_certificates
}

# Run the script
main "$@" 