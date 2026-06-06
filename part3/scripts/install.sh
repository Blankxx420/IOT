#!/bin/bash

curl -fsSL https://get.docker.com | sh
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
sudo usermod -aG docker $USER
sg docker -c "k3d cluster create --config ./config/cluster.yaml"

echo "Waiting for cluster to be ready..."
until kubectl cluster-info &> /dev/null; do
    sleep 2
done

echo "Creation of namespaces..."
kubectl create namespace argocd
kubectl create namespace dev

echo "Installation of Argo CD..."
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Infrastructure is ready !"