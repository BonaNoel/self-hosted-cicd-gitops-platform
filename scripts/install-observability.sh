#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="observability"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --version 3.14.0 \
  --set args[0]=--kubelet-insecure-tls \
  --wait --timeout 5m

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --version 88.6.1 \
  --values "$REPO_ROOT/infra/observability/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

helm upgrade --install loki grafana/loki \
  --namespace "$NAMESPACE" \
  --version 7.3.0 \
  --values "$REPO_ROOT/infra/observability/loki-values.yaml" \
  --wait --timeout 5m

kubectl apply -f "$REPO_ROOT/infra/observability/alloy.yaml"
kubectl rollout status daemonset/alloy --namespace "$NAMESPACE" --timeout=5m
kubectl apply -f "$REPO_ROOT/infra/observability/pipeline-pilot-dashboard.yaml"
kubectl apply -f "$REPO_ROOT/infra/observability/pipeline-pilot-alerts.yaml"

echo
printf 'Observability stack installed.\n'
printf 'Add "127.0.0.1 grafana.local prometheus.local" to /etc/hosts.\n'
printf 'Grafana: http://grafana.local (admin / ChangeMe123!)\n'
printf 'Prometheus: http://prometheus.local\n'
printf 'Check resource metrics: kubectl top pods -A\n'
