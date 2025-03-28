# Easy Magma Orchestrator Setup

A simplified installer for deploying the Magma Orchestrator (v1.8.0) with automatic Kubernetes setup.

## Prerequisites

- Blank Ubuntu 22.04 LTS VM.
- sudo/root access
- At least 4GB RAM and 2 CPU cores
- Basic networking knowledge

## How To Use

### 1. Clone the Repository

```bash
git clone https://github.com/joshualambert/easy-magma-setup.git
cd easy-magma-setup
```

### 2. Make the Install Script Executable

```bash
chmod +x install.sh
```

### 3. Run the Installation Script

```bash
./install.sh
```

This will launch an interactive menu to guide you through the Magma Orchestrator/NMS installation process.

## Installation Options

The script provides the following options:

1. **Set/Update Credentials** - Configure your domain and email, with auto-generated secure passwords
2. **System Check** - Verify your system meets all requirements
3. **Install Dependencies** - Set up required tools and dependencies including lightweight Kubernetes
4. **Setup Cert Manager** - Install certificate management for HTTPS
5. **Generate Certificates** - Create SSL certificates for your domain
6. **Create Secrets** - Set up Kubernetes secrets for secure operation
7. **Install Databases** - Deploy required databases
8. **Install Magma Chart** - Deploy the Magma Orchestrator & NMS
9. **Configure Admin** - Set up the administrator account
10. **Display Status** - Check the deployment status
11. **Troubleshoot** - Run diagnostics for common issues
12. **Cleanup** - Remove failed installations

## Non-Interactive Installation

You can also run the complete installation in one command:

```bash
./install.sh run all
```

This will execute all installation steps in sequence. You'll still need to provide credentials at the beginning.

## Troubleshooting

If you encounter issues during installation, run the troubleshooting tool:

```bash
./install.sh troubleshoot
```

## Cleanup

To remove a failed or unwanted installation:

```bash
./install.sh cleanup
```

## Credentials

After installation, your credentials will be saved in `/tmp/magma-installer/magma-credentials.txt`. Ensure you secure this file or note down the credentials in a secure location.

## License

This project is licensed under the terms of the included LICENSE file.