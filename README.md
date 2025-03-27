# Magma Orchestrator + NMS Installer (Ubuntu 22.04 / K3s)

This repository includes a script to deploy the **Magma Orchestrator** and **NMS (Network Management System)** using K3s (lightweight Kubernetes) on a single-node Ubuntu 22.04 LTS server. This setup uses self-signed TLS certificates.

---

## 🖥️ System Requirements

### OS
- Ubuntu 22.04 LTS (64-bit)

### Hardware (Minimum Recommended for Orchestrator + NMS):
| Component | Minimum |
|----------|---------|
| CPU      | 4 vCPUs |
| RAM      | 8 GB    |
| Disk     | 50 GB SSD |
| Network  | Public IP with ports **80** and **443** forwarded if behind NAT |

---

## 📦 Dependencies (automatically handled in the script)

- K3s (Kubernetes)
- Helm 3
- Git
- OpenSSL
- Magma GitHub repository

---

## 🌐 Domain Requirements
You must own and configure a DNS record pointing your domain to the server's public IP.

Example:
```
YOUREXAMPLEDOMAIN.COM → X.X.X.X
```

---

## 🚀 Installation

1. SSH into your Ubuntu 22.04 server.
2. Clone this repository or copy the script locally.
3. Make the script executable:

```bash
chmod +x install-magma.sh
```

4. Run the installation script:

```bash
./install-magma.sh yourorchestratorurlhere.com youremailhere@fakeemail.com
```

---

## 📁 Script Overview

The script performs the following steps:

1. Installs K3s Kubernetes and Helm.
2. Configures `kubectl` for the current user.
3. Clones the Magma GitHub repo.
4. Installs Cert Manager.
5. Generates a self-signed certificate for the Orchestrator domain.
6. Creates all required Kubernetes secrets.
7. Deploys:
   - Magma Orchestrator
   - Magma NMS (web interface)
8. Outputs the status of all pods and services.

---

## 📍 After Installation

Check your services:

```bash
kubectl get pods -A
kubectl get svc -A
```

Access the NMS at:

```
https://YOUR-PUBLIC-IP-HERE-OR-DOMAIN-HERE
```

> ⚠️ Your browser may warn about the self-signed certificate. You can proceed past the warning or configure a trusted cert later.

---

## 🧪 Notes & Tips

- The script uses self-signed certs. LetsEncrypt support planned in a future release.
- If your orchestrator is behind NAT, ensure ports **80** and **443** are forwarded to your internal IP.
- Reboot after installation if services don’t appear immediately.

---

## 🛠 Troubleshooting

If something goes wrong:
- Check `kubectl get pods -A` for any pods stuck in `CrashLoopBackOff`.
- Check logs for individual pods:

```bash
kubectl logs -n orc8r <pod-name>
```

- Make sure your domain resolves to the server’s IP.

---

## 👤 Maintainer

- **Josh Lambert**
- [josh@lambertmail.xyz](mailto:josh@lambertmail.xyz)
- [joshlambert.xyz]
