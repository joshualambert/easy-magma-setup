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
    
    # Check required commands
    echo "🔍 Checking required commands..."
    for cmd in kubectl helm openssl curl; do
        if command -v $cmd &> /dev/null; then
            echo "✅ $cmd is installed"
            verbose "$($cmd --version)"
        else
            echo "❌ $cmd is not installed"
            exit 1
        fi
    done
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then 
        echo "❌ Please do not run this script as root"
        exit 1
    fi
    
    # Check if running on supported OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        echo "✅ Running on $OS $VERSION"
    else
        echo "⚠️ Could not determine OS version"
    fi
    
    echo "✅ System checks completed!"
}

# Main execution
main() {
    # Check for verbose flag
    if [[ "$*" == *"--verbose"* ]]; then
        VERBOSE=true
        echo "🔊 Verbose mode enabled"
    fi
    
    check_resources
}

# Run the script
main "$@" 