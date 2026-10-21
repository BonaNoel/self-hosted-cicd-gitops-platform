#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="dev"
HPA_NAME="pipeline-pilot"
DEPLOYMENT_NAME="pipeline-pilot"
JOB_NAME="pipeline-pilot-traffic"

REQUESTS="${REQUESTS:-200}"
CPU_MILLIS="${CPU_MILLIS:-600}"
IO_MILLIS="${IO_MILLIS:-25}"
COMPLEXITY="${COMPLEXITY:-20000}"
PAUSE_SECONDS="${PAUSE_SECONDS:-0}"
RAMP_STAGGER_SECONDS="${RAMP_STAGGER_SECONDS:-0}"
WORKERS="${WORKERS:-8}"
SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-5}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-20m}"
SCALE_IN_TIMEOUT_SECONDS="${SCALE_IN_TIMEOUT_SECONDS:-900}"
RUN_LABEL="${RUN_LABEL:-hpa}"
RESULTS_DIR="${RESULTS_DIR:-$HOME/thesis-writing/meresek}"

usage() {
  cat <<'EOF'
HPA autoscaling measurement runner

Environment variables:
  WORKERS                    Parallel traffic pods (default: 8)
  REQUESTS                   Iterations per worker (default: 200)
  CPU_MILLIS                 Simulated CPU work per request (default: 600)
  IO_MILLIS                  Simulated I/O delay per request (default: 25)
  COMPLEXITY                 Simulation complexity (default: 20000)
  PAUSE_SECONDS              Delay between iterations (default: 0)
  RAMP_STAGGER_SECONDS       Delay between indexed workers (default: 0)
  SAMPLE_INTERVAL_SECONDS    HPA/pod sampling interval (default: 5)
  WAIT_TIMEOUT               Traffic Job timeout (default: 20m)
  SCALE_IN_TIMEOUT_SECONDS   Time to observe return to baseline (default: 900)
  RUN_LABEL                  Short label included in the result directory
  RESULTS_DIR                Output root (default: ~/thesis-writing/meresek)

Example:
  WORKERS=8 REQUESTS=200 CPU_MILLIS=600 RUN_LABEL=trial-01 \
    bash scripts/run-hpa-measurement.sh
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

validate_integer() {
  local name="$1"
  local value="$2"
  local minimum="$3"
  local maximum="$4"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < minimum || value > maximum )); then
    printf '%s must be an integer between %s and %s; got %s\n' \
      "$name" "$minimum" "$maximum" "$value" >&2
    exit 2
  fi
}

validate_integer REQUESTS "$REQUESTS" 1 100000
validate_integer CPU_MILLIS "$CPU_MILLIS" 0 30000
validate_integer IO_MILLIS "$IO_MILLIS" 0 30000
validate_integer COMPLEXITY "$COMPLEXITY" 100 500000
validate_integer PAUSE_SECONDS "$PAUSE_SECONDS" 0 3600
validate_integer RAMP_STAGGER_SECONDS "$RAMP_STAGGER_SECONDS" 0 3600
validate_integer WORKERS "$WORKERS" 1 100
validate_integer SAMPLE_INTERVAL_SECONDS "$SAMPLE_INTERVAL_SECONDS" 1 3600
validate_integer SCALE_IN_TIMEOUT_SECONDS "$SCALE_IN_TIMEOUT_SECONDS" 1 7200

if ! [[ "$RUN_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'RUN_LABEL may contain only letters, numbers, dots, underscores, and hyphens.\n' >&2
  exit 2
fi

for command in kubectl jq date; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" >/dev/null
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" >/dev/null
BASELINE_HPA_JSON="$(kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" -o json)"
BASELINE_DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" -o json)"
BASELINE_PODS_JSON="$(kubectl get pods --namespace "$NAMESPACE" -l app.kubernetes.io/name=pipeline-pilot -o json)"
BASELINE_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
BASELINE_AVAILABLE_REPLICAS="$(jq -r '.status.availableReplicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
BASELINE_READY_PODS="$(jq '[.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$BASELINE_PODS_JSON")"
BASELINE_HPA_CURRENT="$(jq -r '.status.currentReplicas // 0' <<< "$BASELINE_HPA_JSON")"
BASELINE_HPA_DESIRED="$(jq -r '.status.desiredReplicas // 0' <<< "$BASELINE_HPA_JSON")"

if (( BASELINE_REPLICAS < 1 )) \
  || (( BASELINE_AVAILABLE_REPLICAS != BASELINE_REPLICAS )) \
  || (( BASELINE_READY_PODS != BASELINE_REPLICAS )) \
  || (( BASELINE_HPA_CURRENT != BASELINE_REPLICAS )) \
  || (( BASELINE_HPA_DESIRED != BASELINE_REPLICAS )); then
  printf 'Refusing to start: HPA and Deployment must be stable at the same Ready replica baseline.\n' >&2
  printf 'HPA current/desired: %s/%s; Deployment available/desired: %s/%s; Ready pods: %s\n' \
    "$BASELINE_HPA_CURRENT" "$BASELINE_HPA_DESIRED" \
    "$BASELINE_AVAILABLE_REPLICAS" "$BASELINE_REPLICAS" "$BASELINE_READY_PODS" >&2
  exit 1
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RUN_LABEL"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR/screenshots"

METADATA_FILE="$RUN_DIR/metadata.txt"
SAMPLES_FILE="$RUN_DIR/hpa-samples.csv"
RESOURCES_FILE="$RUN_DIR/pod-resources.tsv"
TRAFFIC_LOG="$RUN_DIR/traffic.log"

cat > "$METADATA_FILE" <<EOF
Run ID: $RUN_ID
Started UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Namespace: $NAMESPACE
HPA: $HPA_NAME
Traffic profile:
  workers: $WORKERS
  iterations per worker: $REQUESTS
  total iterations: $((WORKERS * REQUESTS))
  expected HTTP requests (3 per iteration): $((WORKERS * REQUESTS * 3))
  cpuMillis: $CPU_MILLIS
  ioMillis: $IO_MILLIS
  complexity: $COMPLEXITY
  pauseSeconds: $PAUSE_SECONDS
  rampStaggerSeconds: $RAMP_STAGGER_SECONDS
  baselineReplicas: $BASELINE_REPLICAS
  sampleIntervalSeconds: $SAMPLE_INTERVAL_SECONDS
  waitTimeout: $WAIT_TIMEOUT
  scaleInTimeoutSeconds: $SCALE_IN_TIMEOUT_SECONDS

EOF

kubectl version --client -o yaml > "$RUN_DIR/kubectl-version.yaml"
kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" -o yaml > "$RUN_DIR/hpa-before.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" -o yaml > "$RUN_DIR/deployment-before.yaml"

printf 'timestamp_utc,hpa_current_replicas,hpa_desired_replicas,hpa_cpu_current_pct,hpa_cpu_target_pct,deployment_desired_replicas,deployment_available_replicas,pods_ready,pods_total\n' \
  > "$SAMPLES_FILE"
printf 'timestamp_utc\tpod\tcpu\tmemory\n' > "$RESOURCES_FILE"

capture_sample() {
  local timestamp hpa_json deployment_json pods_json
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  hpa_json="$(kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" -o json)"
  deployment_json="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" -o json)"
  pods_json="$(kubectl get pods --namespace "$NAMESPACE" -l app.kubernetes.io/name=pipeline-pilot -o json)"

  jq -rn \
    --arg timestamp "$timestamp" \
    --argjson hpa "$hpa_json" \
    --argjson deployment "$deployment_json" \
    --argjson pods "$pods_json" '
      [
        $timestamp,
        ($hpa.status.currentReplicas // 0),
        ($hpa.status.desiredReplicas // 0),
        ([ $hpa.status.currentMetrics[]? | select(.type == "Resource" and .resource.name == "cpu") | (.resource.current.averageUtilization // "NA") ][0] // "NA"),
        ([ $hpa.spec.metrics[]? | select(.type == "Resource" and .resource.name == "cpu") | (.resource.target.averageUtilization // "NA") ][0] // "NA"),
        ($deployment.spec.replicas // 0),
        ($deployment.status.availableReplicas // 0),
        ([ $pods.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) ] | length),
        ($pods.items | length)
      ] | @csv
    ' >> "$SAMPLES_FILE"

  kubectl top pods --namespace "$NAMESPACE" \
    -l app.kubernetes.io/name=pipeline-pilot --no-headers 2>/dev/null \
    | while IFS= read -r pod_line; do
        printf '%s\t%s\n' "$timestamp" "$pod_line"
      done >> "$RESOURCES_FILE"
}

capture_sample
printf 'Measurement started. RUN_ID=%s\nResults: %s\n' "$RUN_ID" "$RUN_DIR"
printf 'Monitor the Grafana dashboard and save screenshots in the screenshots/ directory.\n'
printf 'Sampling interval: %ss. Load: %s workers x %s iterations, staggered by %ss.\n' \
  "$SAMPLE_INTERVAL_SECONDS" "$WORKERS" "$REQUESTS" "$RAMP_STAGGER_SECONDS"

RUN_LABEL="$RUN_LABEL" \
RESULTS_DIR="$RESULTS_DIR" \
REQUESTS="$REQUESTS" \
CPU_MILLIS="$CPU_MILLIS" \
IO_MILLIS="$IO_MILLIS" \
COMPLEXITY="$COMPLEXITY" \
PAUSE_SECONDS="$PAUSE_SECONDS" \
RAMP_STAGGER_SECONDS="$RAMP_STAGGER_SECONDS" \
WORKERS="$WORKERS" \
WAIT_TIMEOUT="$WAIT_TIMEOUT" \
SCALE_IN_TIMEOUT_SECONDS="$SCALE_IN_TIMEOUT_SECONDS" \
  bash "$SCRIPT_DIR/run-observability-traffic-test.sh" > "$TRAFFIC_LOG" 2>&1 &
TRAFFIC_PID=$!

while kill -0 "$TRAFFIC_PID" 2>/dev/null; do
  sleep "$SAMPLE_INTERVAL_SECONDS"
  capture_sample
done

set +e
wait "$TRAFFIC_PID"
TRAFFIC_STATUS=$?
set -e

capture_sample
TRAFFIC_FINISHED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Traffic finished UTC: %s\nTraffic script exit code: %s\n' \
  "$TRAFFIC_FINISHED_UTC" "$TRAFFIC_STATUS" >> "$METADATA_FILE"

printf 'Traffic finished. Sampling until HPA and Deployment return to %s Ready replicas.\n' \
  "$BASELINE_REPLICAS"
SCALE_IN_DEADLINE=$(( $(date +%s) + SCALE_IN_TIMEOUT_SECONDS ))
SCALE_IN_CONSECUTIVE_SAMPLES=0
SCALE_IN_REACHED=false
SCALE_IN_REACHED_UTC=""

while (( $(date +%s) < SCALE_IN_DEADLINE )); do
  sleep "$SAMPLE_INTERVAL_SECONDS"
  capture_sample

  HPA_STATE="$(kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" -o json)"
  DEPLOYMENT_STATE="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" -o json)"
  PODS_STATE="$(kubectl get pods --namespace "$NAMESPACE" -l app.kubernetes.io/name=pipeline-pilot -o json)"
  HPA_CURRENT="$(jq -r '.status.currentReplicas // 0' <<< "$HPA_STATE")"
  HPA_DESIRED="$(jq -r '.status.desiredReplicas // 0' <<< "$HPA_STATE")"
  DEPLOYMENT_DESIRED="$(jq -r '.spec.replicas // 0' <<< "$DEPLOYMENT_STATE")"
  DEPLOYMENT_AVAILABLE="$(jq -r '.status.availableReplicas // 0' <<< "$DEPLOYMENT_STATE")"
  READY_PODS="$(jq '[.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$PODS_STATE")"

  if (( HPA_CURRENT == BASELINE_REPLICAS \
    && HPA_DESIRED == BASELINE_REPLICAS \
    && DEPLOYMENT_DESIRED == BASELINE_REPLICAS \
    && DEPLOYMENT_AVAILABLE == BASELINE_REPLICAS \
    && READY_PODS == BASELINE_REPLICAS )); then
    SCALE_IN_CONSECUTIVE_SAMPLES=$((SCALE_IN_CONSECUTIVE_SAMPLES + 1))
    if (( SCALE_IN_CONSECUTIVE_SAMPLES >= 3 )); then
      SCALE_IN_REACHED=true
      SCALE_IN_REACHED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      break
    fi
  else
    SCALE_IN_CONSECUTIVE_SAMPLES=0
  fi
done

END_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Scale-in baseline replicas: %s\nScale-in returned to baseline: %s\nScale-in observed UTC: %s\nFinished UTC: %s\n' \
  "$BASELINE_REPLICAS" "$SCALE_IN_REACHED" "${SCALE_IN_REACHED_UTC:-not observed before timeout}" "$END_TIME" \
  >> "$METADATA_FILE"
kubectl get hpa "$HPA_NAME" --namespace "$NAMESPACE" -o yaml > "$RUN_DIR/hpa-after.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$NAMESPACE" -o yaml > "$RUN_DIR/deployment-after.yaml"

printf '\nMeasurement finished. Results: %s\n' "$RUN_DIR"
printf 'Scale-in returned to baseline: %s\n' "$SCALE_IN_REACHED"
printf 'Files: metadata.txt, hpa-samples.csv, pod-resources.tsv, traffic.log, screenshots/\n'
if (( TRAFFIC_STATUS != 0 )); then
  printf 'The traffic test failed; see: %s\n' "$TRAFFIC_LOG" >&2
  exit "$TRAFFIC_STATUS"
fi
if [[ "$SCALE_IN_REACHED" != true ]]; then
  printf 'The Deployment did not return to its Ready baseline before the scale-in timeout.\n' >&2
  exit 1
fi
