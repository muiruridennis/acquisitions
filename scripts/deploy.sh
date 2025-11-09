#!/bin/bash
set -e

# Configuration
APP_NAME="acquisitions"
USERNAME="muiruridennis"
IMAGE="$USERNAME/$APP_NAME"
K8S_BASE_DIR="./k8s"

# Default to local environment
ENVIRONMENT="${1:-local}"
IMAGE_TAG="${2:-latest}"

echo "=== Deploying $APP_NAME to $ENVIRONMENT environment ==="

# Build and push Docker image
echo "Building Docker image..."
docker build -t $IMAGE:$IMAGE_TAG .

echo "Pushing Docker image to Docker Hub..."
docker push $IMAGE:$IMAGE_TAG

# Deploy using kustomize
echo "Deploying to Kubernetes ($ENVIRONMENT environment)..."
kubectl apply -k $K8S_BASE_DIR/overlays/$ENVIRONMENT

# Wait a bit for pods to start
echo "Waiting for pods to be ready..."
sleep 10

# Check deployment status
echo "=== Deployment Status ==="
kubectl get pods -n acquisitions -l app=acquisitions-app

echo "=== Services ==="
kubectl get services -n acquisitions

echo "=== HPA Status ==="
kubectl get hpa -n acquisitions

echo "=== Ingress ==="
kubectl get ingress -n acquisitions

echo "Deployment completed successfully!"