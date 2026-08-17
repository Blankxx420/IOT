#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_CONFIG="${SCRIPT_DIR}/cluster.yml"
APPLICATION_MANIFEST="${SCRIPT_DIR}/k8s/application.yml"

if [[ ! -f "$CLUSTER_CONFIG" ]]; then
    echo "Cluster config not found: $CLUSTER_CONFIG"
    exit 1
fi

if ! k3d cluster list 2>/dev/null | grep -q "iot-bonus-cluster"; then
    echo "Creating the k3d bonus cluster..."
    k3d cluster create --config "$CLUSTER_CONFIG"
else
    echo "-> The k3d bonus cluster already exists."
fi

echo "Waiting for the cluster..."
until kubectl cluster-info &> /dev/null; do
    sleep 2
done

kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

if ! command -v helm &> /dev/null; then
    curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod +x /tmp/get_helm.sh
    /tmp/get_helm.sh
fi

helm repo add gitlab https://charts.gitlab.io --force-update >/dev/null 2>&1 || true
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null 2>&1 || true
helm repo update gitlab >/dev/null 2>&1 || true
helm repo update bitnami >/dev/null 2>&1 || true

PGPASS=$(openssl rand -hex 16)
REDISPASS=$(openssl rand -hex 16)
MINIOPASS=$(openssl rand -hex 16)

for release in gitlab-postgresql gitlab-redis gitlab-minio gitlab; do
    if helm list -n gitlab | awk 'NR>1 {print $1}' | grep -qx "$release"; then
        echo "Deleting existing Helm release '$release' before reinstall..."
        helm uninstall "$release" -n gitlab --wait || true
    fi
done

echo "Installation de PostgreSQL..."
helm upgrade --install gitlab-postgresql bitnami/postgresql \
  --namespace gitlab \
  --create-namespace \
  --set fullnameOverride=gitlab-postgresql \
  --set auth.username=gitlab \
  --set auth.password="$PGPASS" \
  --set auth.database=gitlabhq_production \
  --set primary.persistence.size=8Gi \
  --wait --timeout 600s

echo "Installation de Redis..."
helm upgrade --install gitlab-redis bitnami/redis \
  --namespace gitlab \
  --create-namespace \
  --set fullnameOverride=gitlab-redis \
  --set architecture=standalone \
  --set auth.password="$REDISPASS" \
  --wait --timeout 600s

echo "Installation de MinIO..."
MINIO_VALUES="$(mktemp)"
cat > "$MINIO_VALUES" <<EOF
fullnameOverride: gitlab-minio
image:
  repository: bitnami/minio
  tag: latest
  pullPolicy: IfNotPresent
auth:
  rootUser: gitlab
  rootPassword: "${MINIOPASS}"
defaultBuckets: "gitlab-artifacts,gitlab-uploads,gitlab-packages,git-lfs,gitlab-backups,registry"
persistence:
  enabled: false
resourcesPreset: "none"
EOF

helm upgrade --install gitlab-minio bitnami/minio \
  --namespace gitlab \
  --create-namespace \
  -f "$MINIO_VALUES" \
  --wait --timeout 600s
rm -f "$MINIO_VALUES"

kubectl create secret generic gitlab-object-storage -n gitlab --from-literal=connection="provider: AWS
region: us-east-1
aws_access_key_id: gitlab
aws_secret_access_key: $MINIOPASS
endpoint: http://gitlab-minio.gitlab.svc.cluster.local:9000
path_style: true" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-registry-storage -n gitlab --from-literal=config="s3:
  bucket: registry
  accesskey: gitlab
  secretkey: $MINIOPASS
  region: us-east-1
  regionendpoint: http://gitlab-minio.gitlab.svc.cluster.local:9000
  v4auth: true
  pathstyle: true" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-backup-storage -n gitlab --from-literal=config="[default]
access_key = gitlab
secret_key = $MINIOPASS
host_base = gitlab-minio.gitlab.svc.cluster.local:9000
host_bucket = gitlab-minio.gitlab.svc.cluster.local:9000
use_https = False
check_ssl_certificate = False" --dry-run=client -o yaml | kubectl apply -f -

echo "Installation de GitLab (cela peut prendre quelques minutes)..."
helm upgrade --install gitlab gitlab/gitlab \
  --version 10.2.1 \
  --namespace gitlab \
  --create-namespace \
  --set global.hosts.domain=local.gitlab.com \
  --set global.hosts.externalIP=127.0.0.1 \
  --set certmanager-issuer.email=admin@example.com \
  --set global.ingress.configureCertmanager=false \
  --set nginx-ingress.enabled=false \
  --set prometheus.install=false \
  --set global.edition=ce \
  --set global.psql.host=gitlab-postgresql.gitlab.svc.cluster.local \
  --set global.psql.password.secret=gitlab-postgresql \
  --set global.psql.password.key=password \
  --set global.psql.username=gitlab \
  --set global.psql.database=gitlabhq_production \
  --set global.redis.host=gitlab-redis-master.gitlab.svc.cluster.local \
  --set global.redis.auth.secret=gitlab-redis \
  --set global.redis.auth.key=redis-password \
  --set global.appConfig.object_store.enabled=true \
  --set global.appConfig.object_store.connection.secret=gitlab-object-storage \
  --set registry.storage.secret=gitlab-registry-storage \
  --set gitlab.toolbox.backups.objectStorage.config.secret=gitlab-backup-storage \
  --wait --timeout 600s

echo "Récupération du mot de passe administrateur GitLab..."
for i in $(seq 1 60); do
    if kubectl get secret gitlab-gitlab-initial-root-password -n gitlab &> /dev/null; then
        break
    fi
    echo "Waiting for GitLab init secret... ($i/60)"
    kubectl get pods -n gitlab 2>/dev/null || true
    sleep 10
done

if ! kubectl get secret gitlab-gitlab-initial-root-password -n gitlab &> /dev/null; then
    echo "GitLab did not create the initial root secret in time."
    echo "Helm releases in gitlab namespace:"
    helm list -n gitlab || true    kubectl get pods -n gitlab
    kubectl get events -n gitlab --sort-by=.metadata.creationTimestamp | tail -50
    echo "GitLab pods:"
    kubectl get pods -n gitlab || true
    exit 1
fi

echo -n "Mot de passe root GitLab : "
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath="{.data.password}" | base64 --decode
echo ""

if [[ ! -f "$APPLICATION_MANIFEST" ]]; then
    echo "Application manifest not found: $APPLICATION_MANIFEST"
    exit 1
fi

kubectl apply -f "$APPLICATION_MANIFEST"

echo "Bonus ready!"