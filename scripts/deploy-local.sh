#!/bin/bash
set -e

echo "=== Quick Local Deployment ==="

# Build local image matching Kustomize overlay
docker build -t muiruridennis/acquisitions:latest .

# Deploy
kubectl apply -k k8s/overlays/local

# Port forward for easy access (local namespace)
kubectl port-forward -n acquisitions-local service/acquisitions-app 8080:80 &
echo "App available at: http://localhost:8080"
