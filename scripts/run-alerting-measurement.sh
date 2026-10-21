#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
APP_NAMESPACE="${APP_NAMESPACE:-dev}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-pipeline-pilot}"
HPA_NAME="${HPA_NAME:-pipeline-pilot}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_APPLICATION="${ARGO_APPLICATION:-pipeline-pilot}"
PROM_NAMESPACE="${PROM_NAMESPACE:-observability}"
PROM_SERVICE="${PROM_SERVICE:-monitoring-kube-prometheus-prometheus}"
LOCAL_PROM_PORT="${LOCAL_PROM_PORT:-19090}"
ALERT_NAME="${ALERT_NAME:-PipelinePilotDown}"
POLL_SECONDS="${POLL_SECONDS:-5}"
FIRING_TIMEOUT_SECONDS="${FIRING_TIMEOUT_SECONDS:-300}"
HOLD_SECONDS="${HOLD_SECONDS:-45}"
RESOLVE_TIMEOUT_SECONDS="${RESOLVE_TIMEOUT_SECONDS:-180}"
RUN_LABEL="${RUN_LABEL:-alert-down}"
RESULTS_DIR="${RESULTS_DIR:-$HOME/thesis-writing/meresek}"

usage() {
  cat <<'EOF'
Trigger and measure the PipelinePilotDown alert, then restore the application.

WARNING: This briefly scales the application Deployment to zero replicas.
Run only in the demo cluster during a planned test window.

Environment variables:
  APP_NAMESPACE              Application namespace (default: dev)
  DEPLOYMENT_NAME            Deployment name (default: pipeline-pilot)
  HPA_NAME                   HPA name (default: pipeline-pilot)
  ARGO_NAMESPACE             Argo CD namespace (default: argocd)
  ARGO_APPLICATION           Argo CD Application (default: pipeline-pilot)
  PROM_NAMESPACE             Prometheus namespace (default: observability)
  PROM_SERVICE               Prometheus service (default: monitoring-kube-prometheus-prometheus)
  LOCAL_PROM_PORT            Local port-forward port (default: 19090)
  ALERT_NAME                 Alert to observe (default: PipelinePilotDown)
  POLL_SECONDS               Sampling interval (default: 5)
  FIRING_TIMEOUT_SECONDS     Time to wait for firing (default: 300)
  HOLD_SECONDS               Screenshot window while firing (default: 45)
  RESOLVE_TIMEOUT_SECONDS    Time to wait for resolution (default: 180)
  RUN_LABEL                  Result directory label (default: alert-down)
  RESULTS_DIR                Output root (default: ~/thesis-writing/meresek)

Example:
  RUN_LABEL=trial-01 bash scripts/run-alerting-measurement.sh
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for command in kubectl jq curl date; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

validate_positive_integer() {
  local name="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
    printf '%s must be a positive integer; got %s\n' "$name" "$value" >&2
    exit 2
  fi
}

validate_positive_integer LOCAL_PROM_PORT "$LOCAL_PROM_PORT"
validate_positive_integer POLL_SECONDS "$POLL_SECONDS"
validate_positive_integer FIRING_TIMEOUT_SECONDS "$FIRING_TIMEOUT_SECONDS"
validate_positive_integer HOLD_SECONDS "$HOLD_SECONDS"
validate_positive_integer RESOLVE_TIMEOUT_SECONDS "$RESOLVE_TIMEOUT_SECONDS"

if (( LOCAL_PROM_PORT > 65535 )); then
  printf 'LOCAL_PROM_PORT must be between 1 and 65535.\n' >&2
  exit 2
fi
if ! [[ "$RUN_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'RUN_LABEL may contain only letters, numbers, dots, underscores, and hyphens.\n' >&2
  exit 2
fi

kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" >/dev/null
kubectl get hpa "$HPA_NAME" --namespace "$APP_NAMESPACE" >/dev/null
kubectl get prometheus -n "$PROM_NAMESPACE" >/dev/null
kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" >/dev/null

BASELINE_DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
BASELINE_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
BASELINE_IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$BASELINE_DEPLOYMENT_JSON")"
BASELINE_ARGO_JSON="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
BASELINE_ARGO_SYNC="$(jq -r '.status.sync.status // "Unknown"' <<< "$BASELINE_ARGO_JSON")"
BASELINE_ARGO_HEALTH="$(jq -r '.status.health.status // "Unknown"' <<< "$BASELINE_ARGO_JSON")"

if (( BASELINE_REPLICAS < 1 )); then
  printf 'Refusing to start: baseline Deployment replica count is %s.\n' "$BASELINE_REPLICAS" >&2
  exit 1
fi
if [[ "$BASELINE_ARGO_SYNC" != "Synced" || "$BASELINE_ARGO_HEALTH" != "Healthy" ]]; then
  printf 'Refusing to start: Argo CD baseline must be Synced and Healthy (got %s/%s).\n' \
    "$BASELINE_ARGO_SYNC" "$BASELINE_ARGO_HEALTH" >&2
  exit 1
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RUN_LABEL"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR/screenshots"
METADATA_FILE="$RUN_DIR/metadata.txt"
SAMPLES_FILE="$RUN_DIR/alert-timeline.csv"
PORT_FORWARD_LOG="$RUN_DIR/prometheus-port-forward.log"

cat > "$METADATA_FILE" <<EOF
Run ID: $RUN_ID
Alert: $ALERT_NAME
Application: $APP_NAMESPACE/$DEPLOYMENT_NAME
Argo CD Application: $ARGO_NAMESPACE/$ARGO_APPLICATION
Baseline replicas: $BASELINE_REPLICAS
Baseline image: $BASELINE_IMAGE
Polling interval seconds: $POLL_SECONDS
Firing timeout seconds: $FIRING_TIMEOUT_SECONDS
Screenshot hold seconds: $HOLD_SECONDS
Resolution timeout seconds: $RESOLVE_TIMEOUT_SECONDS
Alert rule: PipelinePilotDown (up{job="pipeline-pilot"} == 0 for 2m)
Results timestamps use UTC.

EOF

kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/deployment-before.yaml"
kubectl get hpa "$HPA_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/hpa-before.yaml"
kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml \
  > "$RUN_DIR/argo-before.yaml"

printf 'timestamp_utc,alert_state,up_value,argo_sync,argo_health,deployment_desired,deployment_available,pods_ready,pods_total,image\n' \
  > "$SAMPLES_FILE"

PORT_FORWARD_PID=""
RESTORE_REQUIRED=false

cleanup() {
  if [[ "$RESTORE_REQUIRED" == true ]]; then
    printf 'Restoring Deployment replicas to %s...\n' "$BASELINE_REPLICAS" >&2
    kubectl scale deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" \
      --replicas="$BASELINE_REPLICAS" >&2 || true
  fi
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

kubectl port-forward --namespace "$PROM_NAMESPACE" \
  "service/$PROM_SERVICE" "$LOCAL_PROM_PORT:9090" \
  > "$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!

PROM_URL="http://127.0.0.1:$LOCAL_PROM_PORT"
PORT_FORWARD_DEADLINE=$(( $(date +%s) + 30 ))
PROM_READY=false
while (( $(date +%s) < PORT_FORWARD_DEADLINE )); do
  if curl -fsS "$PROM_URL/api/v1/status/buildinfo" | jq -e '.status == "success"' >/dev/null 2>&1; then
    PROM_READY=true
    break
  fi
  sleep 1
done
if [[ "$PROM_READY" != true ]]; then
  printf 'Could not connect to Prometheus through port-forward; see %s\n' "$PORT_FORWARD_LOG" >&2
  exit 1
fi

get_alert_state() {
  curl -fsS "$PROM_URL/api/v1/alerts" \
    | jq -r --arg name "$ALERT_NAME" \
      '[.data.alerts[]? | select(.labels.alertname == $name) | .state] | if any(.[]; . == "firing") then "firing" elif any(.[]; . == "pending") then "pending" else "inactive" end'
}

get_up_value() {
  local response
  response="$(curl -fsSG "$PROM_URL/api/v1/query" --data-urlencode 'query=up{job="pipeline-pilot"}')"
  jq -r 'if (.data.result | length) == 0 then "missing" else ([.data.result[].value[1]] | join(";")) end' <<< "$response"
}

capture_sample() {
  local timestamp alert_state up_value argo_json argo_sync argo_health deployment_json
  local desired available image pods_json ready total
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  alert_state="$(get_alert_state)"
  up_value="$(get_up_value)"
  argo_json="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
  argo_sync="$(jq -r '.status.sync.status // "Unknown"' <<< "$argo_json")"
  argo_health="$(jq -r '.status.health.status // "Unknown"' <<< "$argo_json")"
  deployment_json="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
  desired="$(jq -r '.spec.replicas // 0' <<< "$deployment_json")"
  available="$(jq -r '.status.availableReplicas // 0' <<< "$deployment_json")"
  image="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$deployment_json")"
  pods_json="$(kubectl get pods --namespace "$APP_NAMESPACE" -l app.kubernetes.io/instance=pipeline-pilot,app.kubernetes.io/name=pipeline-pilot -o json)"
  ready="$(jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$pods_json")"
  total="$(jq '.items | length' <<< "$pods_json")"

  jq -rn \
    --arg timestamp "$timestamp" \
    --arg state "$alert_state" \
    --arg up "$up_value" \
    --arg sync "$argo_sync" \
    --arg health "$argo_health" \
    --arg desired "$desired" \
    --arg available "$available" \
    --arg ready "$ready" \
    --arg total "$total" \
    --arg image "$image" \
    '[$timestamp,$state,$up,$sync,$health,$desired,$available,$ready,$total,$image] | @csv' \
    >> "$SAMPLES_FILE"
}

capture_sample
printf 'Alert measurement started. RUN_ID=%s\nResults: %s\n' "$RUN_ID" "$RUN_DIR"
printf 'Scaling %s/%s from %s replicas to zero to trigger %s.\n' \
  "$APP_NAMESPACE" "$DEPLOYMENT_NAME" "$BASELINE_REPLICAS" "$ALERT_NAME"
printf 'Take screenshots when the alert is firing; they can be saved in screenshots/.\n'

RESTORE_REQUIRED=true
kubectl scale deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" --replicas=0

FIRING_DEADLINE=$(( $(date +%s) + FIRING_TIMEOUT_SECONDS ))
ALERT_FIRED_AT=""
while (( $(date +%s) < FIRING_DEADLINE )); do
  capture_sample
  ALERT_STATE="$(get_alert_state)"
  if [[ "$ALERT_STATE" == "firing" ]]; then
    ALERT_FIRED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Alert %s is FIRING at %s. Holding for %s seconds for screenshots.\n' \
      "$ALERT_NAME" "$ALERT_FIRED_AT" "$HOLD_SECONDS"
    break
  fi
  sleep "$POLL_SECONDS"
done

if [[ -z "$ALERT_FIRED_AT" ]]; then
  printf 'Alert %s did not fire before timeout; restoring the Deployment.\n' "$ALERT_NAME" >&2
  printf 'Result: alert did not fire before timeout.\n' >> "$METADATA_FILE"
  exit 1
fi

HOLD_DEADLINE=$(( $(date +%s) + HOLD_SECONDS ))
while (( $(date +%s) < HOLD_DEADLINE )); do
  sleep "$POLL_SECONDS"
  capture_sample
done

RESTORE_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Restoring Deployment to %s replicas at %s.\n' "$BASELINE_REPLICAS" "$RESTORE_STARTED_AT"
kubectl scale deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" \
  --replicas="$BASELINE_REPLICAS"
RESTORE_REQUIRED=false
kubectl rollout status "deployment/$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" --timeout=5m

RESOLVE_DEADLINE=$(( $(date +%s) + RESOLVE_TIMEOUT_SECONDS ))
ALERT_RESOLVED_AT=""
while (( $(date +%s) < RESOLVE_DEADLINE )); do
  capture_sample
  ALERT_STATE="$(get_alert_state)"
  if [[ "$ALERT_STATE" == "inactive" ]]; then
    ALERT_RESOLVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    break
  fi
  sleep "$POLL_SECONDS"
done

cat >> "$METADATA_FILE" <<EOF
Alert fired UTC: $ALERT_FIRED_AT
Deployment restore started UTC: $RESTORE_STARTED_AT
Alert resolved UTC: ${ALERT_RESOLVED_AT:-not resolved before timeout}
EOF
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/deployment-after.yaml"
kubectl get hpa "$HPA_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/hpa-after.yaml"
kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml \
  > "$RUN_DIR/argo-after.yaml"

if [[ -z "$ALERT_RESOLVED_AT" ]]; then
  printf 'Alert fired but did not resolve before timeout. Results: %s\n' "$RUN_DIR" >&2
  exit 1
fi

printf 'Alert measurement complete. Results: %s\n' "$RUN_DIR"
printf 'Alert fired: %s; resolved: %s\n' "$ALERT_FIRED_AT" "$ALERT_RESOLVED_AT"
printf 'Files: metadata.txt, alert-timeline.csv, before/after YAML snapshots, screenshots/\n'
