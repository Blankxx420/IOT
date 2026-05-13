#!/bin/bash

while ! nc -z 192.168.56.110 6443; do
    echo "Waiting for the server to be ready..."
    sleep 5
done

curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=mytoken123 sh -s - --node-ip=192.168.56.111