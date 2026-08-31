#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-controller-v1.15.1}"

kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/kind/deploy.yaml"

echo "Waiting for ingress-nginx controller to become ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo
printf 'ingress-nginx is ready.\n'
