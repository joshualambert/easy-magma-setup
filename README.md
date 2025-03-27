# Magma Orchestrator + NMS Installer (Ubuntu 22.04 / K3s)

This repository provides a robust script for deploying **Magma Orchestrator** and **NMS (Network Management System)** on a single-node Ubuntu 22.04 LTS server using K3s (lightweight Kubernetes). The installation uses self-signed certificates and is designed for simplicity and reliability.

---

## 🖥️ System Requirements

### OS
- Ubuntu 22.04 LTS (64-bit)

### Hardware (Minimum Recommended)
| Component | Minimum |
|----------|---------|
| CPU      | 4 vCPUs |
| RAM      | 8 GB    |
| Disk     | 50 GB SSD |
| Network  | Public IP with accessible ports for web access |

This script was developed against the **AmericanCloud** webhost. Check them out at [americancloud.com](https://americancloud.com/).

---

## 📦 Dependencies

All dependencies are automatically installed by the script:
- K3s (Lightweight Kubernetes)
- Helm 3
- Git
- OpenSSL
- Magma GitHub repository

---

## 🌐 Domain Setup

You must own and configure a DNS record pointing to your server's public IP.

Example:
```
magma.yourdomain.com → X.X.X.X
```

---

## 🚀 Installation

1. SSH into your Ubuntu 22.04 server
2. Clone this repository or copy the script to your server
3. Make the script executable:

```bash
chmod +x install_magma.sh
```

4. Run the script with your domain and email:

```bash
./install_magma.sh yourdomain.com your@email.com
```

### Additional Options

The script supports several command-line options:

```bash
# Enable verbose output for detailed logs
./install_magma.sh yourdomain.com your@email.com --verbose

# Run troubleshooting checks on an existing installation
./install_magma.sh troubleshoot

# Clean up a failed installation before trying again
./install_magma.sh cleanup
```

---

## 🛠️ Script Features

The installation script:

1. Generates and saves secure credentials at the beginning of installation
2. Installs and configures K3s Kubernetes and Helm
3. Clones the Magma repository and installs required components
4. Sets up databases (PostgreSQL for Orchestrator, MySQL for NMS)
5. Deploys Magma Orchestrator and NMS web interface
6. Creates an admin user for immediate access
7. Provides clear progress indicators at each step
8. Saves all credentials to a secure file for future reference

---

## 📱 Accessing Your Installation

After successful installation, you'll receive:
- URL to access the NMS interface
- Admin credentials for login
- Database passwords and access information

All credentials are saved to `magma-credentials.txt` in your home directory.

---

## ⚠️ Troubleshooting

If you encounter issues during installation:

1. Use the built-in troubleshooting tool:
```bash
./install_magma.sh troubleshoot
```

2. Check pod status:
```bash
kubectl get pods --all-namespaces
```

3. View logs for specific pods:
```bash
kubectl logs -n orc8r POD_NAME
```

4. For database issues:
```bash
kubectl logs -n db $(kubectl get pods -n db -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
```

5. If you need to start over:
```bash
./install_magma.sh cleanup
```

---

## 📝 Notes & Limitations

- The installation uses self-signed certificates by default
- For a production environment, consider implementing proper TLS certificates
- The default configuration uses a NodePort service type - configure proper ingress for production use
- Database SSL is disabled by default for easier setup - enable it for production deployments

---

## 👤 Maintainer

- **Josh Lambert**
- [josh@lambertmail.xyz](mailto:josh@lambertmail.xyz)
- [joshlambert.xyz](https://joshlambert.xyz)

---

## 🔄 Updates & Contributions

This installer is actively maintained. For issues, feature requests, or contributions:
- Open an issue on the GitHub repository
- Submit a pull request with improvements
