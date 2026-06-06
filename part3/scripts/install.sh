#!/bin/bash

curl -fsSL https://get.docker.com | sh
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
sudo usermod -aG docker $USER
sg docker -c "k3d cluster create mycluster"