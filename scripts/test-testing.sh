#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="frontend"
DEPLOYMENT="frontend"

echo "Checking pods..."
kubectl get pods -n "$NAMESPACE"

echo "Checking deployment..."
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"

echo "Waiting for rollout..."
kubectl rollout status \
  deployment/"$DEPLOYMENT" \
  -n "$NAMESPACE" \
  --timeout=300s

echo "Checking ingress..."
kubectl get ingress -n "$NAMESPACE"

echo "Getting ALB DNS..."

ALB_DNS=$(kubectl get ingress myapp \
  -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$ALB_DNS" ]; then
    echo "ALB DNS not available"
    exit 1
fi

echo "ALB: $ALB_DNS"

echo "Waiting for application..."

for i in {1..30}; do

    if curl -fsS "http://${ALB_DNS}/health"; then
        echo
        echo "Testing health check PASSED"
        exit 0
    fi

    echo "Waiting..."
    sleep 10

done

echo "Testing health check FAILED"
exit 1