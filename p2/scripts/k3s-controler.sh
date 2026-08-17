#!/bin/bash

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=192.168.56.110 --tls-san=192.168.56.110 --write-kubeconfig-mode=644" K3S_TOKEN=mytoken123 sh -

until kubectl get nodes > /dev/null 2>&1; do
    echo "Waiting for K3s to be ready..."
    sleep 5
done

kubectl apply -R -f /vagrant/config/
