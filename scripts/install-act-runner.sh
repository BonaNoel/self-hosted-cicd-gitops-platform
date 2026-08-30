#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="mgmt"
GITEA_URL="${GITEA_URL:-http://gitea.local}"
GITEA_ADMIN_USERNAME="${GITEA_ADMIN_USERNAME:-gitea_admin}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-ChangeMe123!}"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required to parse the Gitea runner registration token.\n' >&2
  exit 1
fi

if ! kubectl get secret act-runner-registration -n "$NAMESPACE" >/dev/null 2>&1; then
  TOKEN=$(curl -sf -u "$GITEA_ADMIN_USERNAME:$GITEA_ADMIN_PASSWORD" -X POST \
    "$GITEA_URL/api/v1/admin/actions/runners/registration-token" \
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
printf 'act_runner deployed.\n'
