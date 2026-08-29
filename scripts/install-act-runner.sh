#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="mgmt"

if ! kubectl get secret act-runner-registration -n "$NAMESPACE" >/dev/null 2>&1; then
  TOKEN=$(curl -sf -u gitea_admin:ChangeMe123! -X POST \
    http://gitea.local/api/v1/admin/actions/runners/registration-token \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
  kubectl create secret generic act-runner-registration \
    --namespace "$NAMESPACE" \
    --from-literal=token="$TOKEN"
else
  echo "act-runner-registration secret already exists, reusing it."
fi

kubectl apply -f "$REPO_ROOT/infra/act-runner/deployment.yaml"

kubectl rollout status deployment act-runner -n "$NAMESPACE" --timeout=180s

echo
printf 'act_runner deployed. Check registration: curl -u gitea_admin:ChangeMe123! http://gitea.local/api/v1/admin/actions/runners\n'
