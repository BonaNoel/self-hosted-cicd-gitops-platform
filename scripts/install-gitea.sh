#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="mgmt"

helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null
helm repo update gitea-charts >/dev/null

helm upgrade --install gitea gitea-charts/gitea \
  --namespace "$NAMESPACE" \
  --values "$REPO_ROOT/infra/gitea/values.yaml" \
  --wait --timeout 5m

echo
printf 'Gitea installed in namespace %s.\n' "$NAMESPACE"
printf 'Add "127.0.0.1 gitea.local" to /etc/hosts, then browse to http://gitea.local\n'
printf 'Admin login: gitea_admin / ChangeMe123! (change via infra/gitea/values.yaml before real use)\n'
