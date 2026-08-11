#!/bin/bash
#!/bin/bash


k3d cluster create --config ./cluster.yaml

echo "Attente du cluster..."
until kubectl cluster-info &> /dev/null; do
    sleep 2
done

# 2. Création du namespace GitLab
kubectl create namespace gitlab

# 3. Installation de GitLab via Helm
helm repo add gitlab https://charts.gitlab.io
helm repo update

echo "Installation de GitLab (cela peut prendre quelques minutes)..."
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.hosts.domain=local.gitlab.com \
  --set global.hosts.externalIP=127.0.0.1 \
  --set certmanager-issuer.email=admin@example.com \
  --set global.ingress.configureCertmanager=false \
  --set nginx-ingress.enabled=false \
  --set prometheus.install=false \
  --set global.edition=ce

# 4. Récupération du mot de passe root initial
echo "Récupération du mot de passe administrateur GitLab..."
until kubectl get secret gitlab-gitlab-initial-root-password -n gitlab &> /dev/null; do
    sleep 5
done

echo -n "Mot de passe root GitLab : "
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath="{.data.password}" | base64 --decode
echo ""

# 5. Déploiement de l'application Argo CD pointant vers GitLab
kubectl apply -f ./k8s/application.yaml

echo "Bonus prêt !"