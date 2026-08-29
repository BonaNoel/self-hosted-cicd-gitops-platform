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

# gitea.local is served over plain HTTP via ingress-nginx; without this, containerd/CI docker
# daemons default to HTTPS and fail cert validation against ingress-nginx's default cert.
CLUSTER_NAME="thesis-cluster"
for node in $(kind get nodes --name "$CLUSTER_NAME" 2>/dev/null); do
  docker exec "$node" mkdir -p /etc/containerd/certs.d/gitea.local
  printf 'server = "http://gitea.local"\n\n[host."http://gitea.local"]\n  capabilities = ["pull", "resolve"]\n' \
    | docker exec -i "$node" cp /dev/stdin /etc/containerd/certs.d/gitea.local/hosts.toml
done

echo
printf 'Gitea installed in namespace %s.\n' "$NAMESPACE"
printf 'Add "127.0.0.1 gitea.local" to /etc/hosts, then browse to http://gitea.local\n'
printf 'Admin login: gitea_admin / ChangeMe123! (change via infra/gitea/values.yaml before real use)\n'
