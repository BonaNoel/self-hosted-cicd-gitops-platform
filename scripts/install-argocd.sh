#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="argocd"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace "$NAMESPACE" \
  --values "$REPO_ROOT/infra/argocd/values.yaml" \
  --wait --timeout 5m

echo
printf 'Argo CD installed in namespace %s.\n' "$NAMESPACE"
printf 'Add "127.0.0.1 argocd.local" to /etc/hosts (WSL and Windows), then browse to http://argocd.local\n'
printf 'Admin password: kubectl -n %s get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d\n' "$NAMESPACE"
