#!/bin/bash

if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
    echo "Docker n'est pas installé ou opérationnel. Installation..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "Docker installé."
else
    echo "-> Docker est déjà installé."
fi

# 2. Vérification et installation de k3d
if ! command -v k3d &> /dev/null; then
    echo "k3d n'est pas installé. Installation..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    echo "k3d installé."
else
    echo "-> k3d est déjà installé."
fi

# 3. Vérification et installation de kubectl
if ! command -v kubectl &> /dev/null; then
    echo "kubectl n'est pas installé. Installation..."
    STABLE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${STABLE_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "kubectl installé."
else
    echo "-> kubectl est déjà installé."
fi

CLUSTER_NAME="iot-cluster" 
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
    echo "Création du cluster k3d..."
    k3d cluster create --config ./config/k3d_config.yml
else
    echo "-> Le cluster k3d existe déjà."
fi

echo "Attente que le cluster soit prêt..."
until kubectl cluster-info &> /dev/null; do
    sleep 2
done

echo "Vérification des namespaces..."
for ns in argocd dev; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        kubectl create namespace "$ns"
        echo "Namespace '$ns' créé."
    else
        echo "-> Le namespace '$ns' existe déjà."
    fi
done

if ! kubectl get deployment argocd-server -n argocd &> /dev/null; then
    echo "Installation d'Argo CD..."
    kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
    echo "-> Argo CD est déjà installé."
fi

echo "Infrastructure prête !"

echo "Lancement du port-forward (Ctrl+C pour arrêter)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443