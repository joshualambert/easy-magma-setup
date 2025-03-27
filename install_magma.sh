#!/bin/bash

set -e

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <ORC8R_DOMAIN> <EMAIL>"
    exit 1
fi

ORC8R_DOMAIN=$1
EMAIL=$2
ORC8R_DB_PWD=$(openssl rand -hex 12)
NMS_DB_PWD=$(openssl rand -hex 12)
ADMIN_PASSWORD=$(openssl rand -hex 12)

# System update and K3s installation
sudo apt update && sudo apt upgrade -y
curl -sfL https://get.k3s.io | sh -

# Configure kubectl for current user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config

# Persist KUBECONFIG across sessions
if ! grep -q 'export KUBECONFIG=$HOME/.kube/config' ~/.bashrc; then
  echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
fi

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Clone Magma repo
git clone --depth=1 https://github.com/magma/magma.git
cd magma/orc8r/cloud/helm

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager || true
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.5.3 \
  --set installCRDs=true

# Export Helm setting
export HELM_EXPERIMENTAL_OCI=1

# Create Orchestrator TLS certs
cd ../../tools/helm
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout controller.key \
  -out controller.crt \
  -subj "/CN=${ORC8R_DOMAIN}"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout certifier.key \
  -out certifier.pem \
  -subj "/CN=certifier.magma.com"

openssl genrsa -out bootstrapper.key 2048
openssl req -x509 -new -nodes -key bootstrapper.key -days 365 \
  -out rootCA.pem -subj "/CN=rootCA"

openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout admin_operator.key.pem \
  -out admin_operator.pem \
  -subj "/CN=admin_operator"

kubectl create namespace orc8r || true

# Create required secrets WITHOUT NMS CERTS to avoid triggering nginx ssl config
kubectl -n orc8r create secret generic orc8r-secrets-certs \
  --from-file=controller.crt=controller.crt \
  --from-file=controller.key=controller.key \
  --from-file=rootCA.pem=rootCA.pem \
  --from-file=certifier.pem=certifier.pem \
  --from-file=certifier.key=certifier.key \
  --from-file=bootstrapper.key=bootstrapper.key \
  --from-file=admin_operator.pem=admin_operator.pem \
  --from-file=admin_operator.key.pem=admin_operator.key.pem || true

kubectl -n orc8r create secret generic orc8r-secrets-envdir \
  --from-literal=DATABASE_SOURCE="dbname=orc8r user=orc8r password=$ORC8R_DB_PWD host=orc8r-postgres" \
  --from-literal=CONTROLLER_SERVICES="ACCESSD,ACTIVATIOND,AGGREGATOR,BOOTSTRAPPER,CERTIFIER,DEVICE,DISPATCHER,EVENTD,LOGS,METRICSD,OBSIDIAN,POLICYDB,SERVICE_REGISTRY,SMSSTORE,STATE,STREAMER,SUBSCRIBERDB,SWAGGER,UPGRADE,CONFIGURATION,METERINGD_RECORDS,DIRECTORYD" || true

# Create metrics config
cat > /tmp/metricsd.yml <<EOF
profile: "prometheus"
prometheusQueryAddress: "http://orc8r-prometheus:9090"
prometheusPushAddresses:
  - "http://orc8r-prometheus-cache:9091/metrics"
alertmanagerApiURL: "http://orc8r-alertmanager:9093/api/v2/alerts"
prometheusConfigServiceURL: "http://orc8r-config-manager:9100"
alertmanagerConfigServiceURL: "http://orc8r-config-manager:9101"
EOF

kubectl delete secret orc8r-secrets-configs -n orc8r || true
kubectl -n orc8r create secret generic orc8r-secrets-configs-orc8r \
  --from-file=metricsd.yml=/tmp/metricsd.yml || true

# Go back to the helm chart folder
cd ../../cloud/helm

# Patch deprecated API version
echo "Patching deprecated policy/v1beta1 to policy/v1..."
grep -rl 'policy/v1beta1' ./orc8r | xargs sed -i 's|policy/v1beta1|policy/v1|g'

# Install Postgres for Orchestrator and NMS
kubectl create namespace db || true
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install orc8r-postgres bitnami/postgresql \
  --namespace db \
  --set postgresqlUsername=orc8r \
  --set postgresqlPassword=$ORC8R_DB_PWD \
  --set postgresqlDatabase=orc8r

helm install nms-mysql bitnami/mysql \
  --namespace db \
  --set auth.username=nms \
  --set auth.password=$NMS_DB_PWD \
  --set auth.database=nms

# Create Helm values file
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
EOF

# Install Orchestrator
helm dependency update orc8r
helm install orc8r ./orc8r -f orc8r-values.yaml --namespace orc8r --create-namespace --wait --timeout 10m

# Wait for critical services before creating admin user
echo "⏳ Waiting for Orchestrator core pods to be ready..."
REQUIRED_COMPONENTS=(magmalte orchestrator obsidian service-registry)

for component in "${REQUIRED_COMPONENTS[@]}"; do
  until kubectl -n orc8r get pods -l app.kubernetes.io/component="$component" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
    echo "🔄 Waiting for $component pod to be running..."
    sleep 10
  done
  echo "✅ $component is ready."
done

MAGMALTE_POD=$(kubectl -n orc8r get pods -l app.kubernetes.io/component=magmalte -o jsonpath='{.items[0].metadata.name}')

echo "👤 Creating admin user..."
kubectl -n orc8r exec -it "$MAGMALTE_POD" -- \
  magmalte/scripts/create_admin_user.sh "$EMAIL" "$ADMIN_PASSWORD"

# Show status
kubectl get pods -A
kubectl get svc -A

# Output final details
echo "✅ Magma Orchestrator + NMS deployed successfully!"
echo "🌐 Access NMS at: https://${ORC8R_DOMAIN}"
echo "👤 Admin Email: ${EMAIL}"
echo "🔑 Admin Password: ${ADMIN_PASSWORD}"
echo "🐘 Orchestrator DB Password: ${ORC8R_DB_PWD}"
echo "🐬 NMS MySQL Password: ${NMS_DB_PWD}"
