#!/bin/bash

# Enable/disable verbose output
VERBOSE=false

# Constants
MAGMA_VERSION="v1.8.0"
WORK_DIR="/tmp/magma-installer"
CUSTOM_CHART_DIR="$WORK_DIR/magma-custom-chart"
CERTS_DIR="$WORK_DIR/magma_certs"
CREDENTIALS_FILE="$WORK_DIR/magma-credentials.txt"
SCRIPTS_DIR="$(pwd)/scripts"

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
        return 1
    fi
    return 0
}

# Function to setup working directory
setup_work_dir() {
    echo "📁 Setting up working directory..."
    mkdir -p "$WORK_DIR"
    chmod 700 "$WORK_DIR"
    
    # Create subdirectories
    mkdir -p "$CUSTOM_CHART_DIR"
    mkdir -p "$CERTS_DIR"
    
    verbose "Created working directory: $WORK_DIR"
}

# Function to get credentials from user
get_credentials() {
    echo "🔐 Please provide the following information:"
    read -p "Enter ORC8R_DOMAIN: " ORC8R_DOMAIN
    read -p "Enter EMAIL: " EMAIL
    
    # Generate passwords
    ORC8R_DB_PWD=$(openssl rand -hex 12)
    NMS_DB_PWD=$(openssl rand -hex 12)
    ADMIN_PASSWORD=$(openssl rand -hex 12)
    
    # Save credentials to file
    echo "Saving credentials to $CREDENTIALS_FILE..."
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
    
    echo "✅ Credentials saved successfully."
    read -p "Press Enter to continue..."
}

# Function to display credentials
display_credentials() {
    if [ -f "$CREDENTIALS_FILE" ]; then
        echo "🔐 Current Credentials:"
        echo "----------------------------------------"
        cat "$CREDENTIALS_FILE"
        echo "----------------------------------------"
    else
        echo "❌ No credentials found. Please run option 1 first."
    fi
}

# Function to run a script with proper environment variables
run_script() {
    local script="$1"
    local description="$2"
    
    echo "🚀 Running $description..."
    
    # Export necessary variables for child scripts
    export WORK_DIR
    export CUSTOM_CHART_DIR
    export CERTS_DIR
    export CREDENTIALS_FILE
    export VERBOSE
    export MAGMA_VERSION
    
    # Run the script
    if [ "$VERBOSE" = true ]; then
        bash "$script" --verbose
    else
        bash "$script"
    fi
    
    local result=$?
    if [ $result -ne 0 ]; then
        echo "❌ Script failed with exit code $result"
        return $result
    fi
    return 0
}

# Function to display the main menu
show_menu() {
    clear
    echo "==========================================="
    echo "Magma Orchestrator Installation Menu"
    echo "==========================================="
    echo "1. Set/Update Credentials"
    echo "2. System Check"
    echo "3. Install Dependencies"
    echo "4. Setup Cert Manager"
    echo "5. Generate Certificates"
    echo "6. Create Secrets"
    echo "7. Install Databases"
    echo "8. Install Magma Chart"
    echo "9. Configure Admin"
    echo "10. Display Status"
    echo "11. Troubleshoot"
    echo "12. Cleanup"
    echo "0. Exit"
    echo "==========================================="
    display_credentials
    echo "==========================================="
}

# Function to handle menu selection
handle_menu_selection() {
    local choice="$1"
    
    case $choice in
        1)
            echo "🔐 Setting up credentials..."
            get_credentials
            ;;
        2)
            echo "🔍 Running system check..."
            run_script "$SCRIPTS_DIR/01_check_system.sh" "system checks"
            ;;
        3)
            echo "📦 Installing dependencies..."
            run_script "$SCRIPTS_DIR/02_install_dependencies.sh" "dependency installation"
            ;;
        4)
            echo "🔒 Setting up cert-manager..."
            run_script "$SCRIPTS_DIR/03_setup_cert_manager.sh" "cert-manager setup"
            ;;
        5)
            echo "🔏 Generating certificates..."
            run_script "$SCRIPTS_DIR/04_generate_certs.sh" "certificate generation"
            ;;
        6)
            echo "🔐 Creating secrets..."
            run_script "$SCRIPTS_DIR/05_create_secrets.sh" "secret creation"
            ;;
        7)
            echo "🐘 Installing databases..."
            run_script "$SCRIPTS_DIR/06_install_databases.sh" "database installation"
            ;;
        8)
            echo "📊 Installing Magma chart..."
            run_script "$SCRIPTS_DIR/07_install_chart.sh" "Magma chart installation"
            ;;
        9)
            echo "👤 Configuring admin..."
            run_script "$SCRIPTS_DIR/09_configure_admin.sh" "admin configuration"
            ;;
        10)
            echo "📊 Displaying status..."
            run_script "$SCRIPTS_DIR/10_display_status.sh" "status display"
            ;;
        11)
            echo "🔧 Running troubleshooting..."
            run_script "$SCRIPTS_DIR/troubleshoot.sh" "troubleshooting"
            ;;
        12)
            echo "🧹 Running cleanup..."
            run_script "$SCRIPTS_DIR/cleanup.sh" "cleanup"
            ;;
        0)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please try again."
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# Function to run all steps
run_all_steps() {
    echo "🚀 Starting complete Magma Orchestrator deployment..."
    
    # Check for credentials first
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "❌ No credentials found. Please set credentials first (option 1)."
        return 1
    fi
    
    # Run each component script
    run_script "$SCRIPTS_DIR/01_check_system.sh" "system checks" || return 1
    run_script "$SCRIPTS_DIR/02_install_dependencies.sh" "dependency installation" || return 1
    run_script "$SCRIPTS_DIR/03_setup_cert_manager.sh" "cert-manager setup" || return 1
    run_script "$SCRIPTS_DIR/04_generate_certs.sh" "certificate generation" || return 1
    run_script "$SCRIPTS_DIR/05_create_secrets.sh" "secret creation" || return 1
    run_script "$SCRIPTS_DIR/06_install_databases.sh" "database installation" || return 1
    
    echo "⚠️ About to install Magma Orchestrator."
    read -p "Press Enter to continue or Ctrl+C to stop here..."
    
    run_script "$SCRIPTS_DIR/07_install_chart.sh" "Magma chart installation" || return 1
    run_script "$SCRIPTS_DIR/09_configure_admin.sh" "admin configuration" || return 1
    run_script "$SCRIPTS_DIR/10_display_status.sh" "status display" || return 1
    
    echo "🎉 Magma Orchestrator deployment complete!"
}

# Main execution
main() {
    # Setup working directory
    setup_work_dir
    
    # Check if running in non-interactive mode
    if [ "$#" -ge 2 ]; then
        # Non-interactive mode - run all steps
        check_args "$@"
        run_all_steps
        exit $?
    fi
    
    # Interactive mode
    while true; do
        show_menu
        read -p "Enter your choice (0-12): " choice
        handle_menu_selection "$choice"
    done
}

# If called with 'troubleshoot' argument, run troubleshooting
if [ "$1" == "troubleshoot" ]; then
    setup_work_dir
    bash "$SCRIPTS_DIR/troubleshoot.sh"
    exit 0
fi

# If called with 'cleanup' argument, cleanup failed installation
if [ "$1" == "cleanup" ]; then
    setup_work_dir
    bash "$SCRIPTS_DIR/cleanup.sh"
    exit 0
fi

# Run the script
main "$@" 