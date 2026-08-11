#!/bin/bash

k3d cluster create --config ./cluster.yml

echo "Attente du cluster..."
until kubectl cluster-info &> /dev/null; do
    sleep 2
done

# 2. Création du namespace GitLab
kubectl create namespace gitlab

# 3. Installation de GitLab via Helm
if ! command -v helm &> /dev/null; then
    curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod +x /tmp/get_helm.sh
    /tmp/get_helm.sh
fi

helm repo add gitlab https://charts.gitlab.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Chart v10+ dropped the bundled PostgreSQL/Redis/object storage subcharts,
# so they have to be deployed and wired in separately.
PGPASS=$(openssl rand -hex 16)
REDISPASS=$(openssl rand -hex 16)
MINIOPASS=$(openssl rand -hex 16)

echo "Installation de PostgreSQL..."
helm install gitlab-postgresql bitnami/postgresql \
  --namespace gitlab \
  --set fullnameOverride=gitlab-postgresql \
  --set auth.username=gitlab \
  --set auth.password="$PGPASS" \
  --set auth.database=gitlabhq_production \
  --set primary.persistence.size=8Gi \
  --wait --timeout 600s

echo "Installation de Redis..."
helm install gitlab-redis bitnami/redis \
  --namespace gitlab \
  --set fullnameOverride=gitlab-redis \
  --set architecture=standalone \
  --set auth.password="$REDISPASS" \
  --wait --timeout 600s

echo "Installation de MinIO..."
helm install gitlab-minio bitnami/minio \
  --namespace gitlab \
  --set fullnameOverride=gitlab-minio \
  --set auth.rootUser=gitlab \
  --set auth.rootPassword="$MINIOPASS" \
  --set defaultBuckets="gitlab-artifacts,gitlab-uploads,gitlab-packages,git-lfs,gitlab-backups,registry" \
  --set persistence.size=8Gi \
  --wait --timeout 600s

kubectl create secret generic gitlab-object-storage -n gitlab --from-literal=connection="provider: AWS
region: us-east-1
aws_access_key_id: gitlab
aws_secret_access_key: $MINIOPASS
endpoint: http://gitlab-minio.gitlab.svc.cluster.local:9000
path_style: true"

kubectl create secret generic gitlab-registry-storage -n gitlab --from-literal=config="s3:
  bucket: registry
  accesskey: gitlab
  secretkey: $MINIOPASS
  region: us-east-1
  regionendpoint: http://gitlab-minio.gitlab.svc.cluster.local:9000
  v4auth: true
  pathstyle: true"

kubectl create secret generic gitlab-backup-storage -n gitlab --from-literal=config="[default]
access_key = gitlab
secret_key = $MINIOPASS
host_base = gitlab-minio.gitlab.svc.cluster.local:9000
host_bucket = gitlab-minio.gitlab.svc.cluster.local:9000
use_https = False
check_ssl_certificate = False"

echo "Installation de GitLab (cela peut prendre quelques minutes)..."
helm install gitlab gitlab/gitlab \
  --version 10.2.1 \
  --namespace gitlab \
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
  --set gitlab.toolbox.backups.objectStorage.config.secret=gitlab-backup-storage

# 4. Récupération du mot de passe root initial
echo "Récupération du mot de passe administrateur GitLab..."
until kubectl get secret gitlab-gitlab-initial-root-password -n gitlab &> /dev/null; do
    sleep 5
done

echo -n "Mot de passe root GitLab : "
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath="{.data.password}" | base64 --decode
echo ""

# 5. Déploiement de l'application Argo CD pointant vers GitLab
kubectl apply -f ./k8s/application.yml

echo "Bonus prêt !"