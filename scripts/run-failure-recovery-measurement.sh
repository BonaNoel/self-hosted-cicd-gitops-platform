#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

GIT_REMOTE="${GIT_REMOTE:-gitea}"
GIT_BRANCH="${GIT_BRANCH:-development}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_APPLICATION="${ARGO_APPLICATION:-pipeline-pilot}"
APP_NAMESPACE="${APP_NAMESPACE:-dev}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-pipeline-pilot}"
POLL_SECONDS="${POLL_SECONDS:-2}"
FAILURE_TIMEOUT_SECONDS="${FAILURE_TIMEOUT_SECONDS:-900}"
RECOVERY_TIMEOUT_SECONDS="${RECOVERY_TIMEOUT_SECONDS:-900}"
BASELINE_TIMEOUT_SECONDS="${BASELINE_TIMEOUT_SECONDS:-600}"
STABLE_SAMPLES="${STABLE_SAMPLES:-3}"
RUN_LABEL="${RUN_LABEL:-failure-recovery}"
RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/thesis-writing/meresek}"
APP_SELECTOR="app.kubernetes.io/instance=pipeline-pilot,app.kubernetes.io/name=pipeline-pilot"

usage() {
  cat <<'EOF'
Measure GitOps failure detection and recovery for an invalid application image tag.

Start this watcher before changing only
apps/pipeline-pilot/helm/pipeline-pilot/image-tag.yaml on the watched branch.
After the watcher reports ImagePullBackOff/ErrImagePull, restore the exact known-good
image tag from metadata.txt and push that recovery commit. The script observes state;
it does not edit Git, push commits, or modify Kubernetes resources.

Environment variables:
  GIT_REMOTE                Git remote name (default: gitea)
  GIT_BRANCH                Watched branch (default: development)
  ARGO_NAMESPACE            Argo CD namespace (default: argocd)
  ARGO_APPLICATION          Argo CD Application (default: pipeline-pilot)
  APP_NAMESPACE             Application namespace (default: dev)
  DEPLOYMENT_NAME           Deployment name (default: pipeline-pilot)
  POLL_SECONDS              Poll interval (default: 2)
  FAILURE_TIMEOUT_SECONDS   Wait for failure revision and pod pull error (default: 900)
  RECOVERY_TIMEOUT_SECONDS  Wait for recovery revision and healthy rollout (default: 900)
  BASELINE_TIMEOUT_SECONDS  Wait for a stable starting baseline (default: 600)
  STABLE_SAMPLES            Consecutive healthy recovery samples (default: 3)
  RUN_LABEL                 Result directory label (default: failure-recovery)
  RESULTS_DIR               Output root (default: <repo>/thesis-writing/meresek)

EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

validate_positive_integer() {
  local name="$1"
  local value="$2"
  local maximum="${3:-7200}"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > maximum )); then
    printf '%s must be an integer between 1 and %s; got %s\n' \
      "$name" "$maximum" "$value" >&2
    exit 2
  fi
}

validate_positive_integer POLL_SECONDS "$POLL_SECONDS"
validate_positive_integer FAILURE_TIMEOUT_SECONDS "$FAILURE_TIMEOUT_SECONDS"
validate_positive_integer RECOVERY_TIMEOUT_SECONDS "$RECOVERY_TIMEOUT_SECONDS"
validate_positive_integer BASELINE_TIMEOUT_SECONDS "$BASELINE_TIMEOUT_SECONDS"
validate_positive_integer STABLE_SAMPLES "$STABLE_SAMPLES" 100

if ! [[ "$RUN_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'RUN_LABEL may contain only letters, numbers, dots, underscores, and hyphens.\n' >&2
  exit 2
fi

for command in git kubectl jq date; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if ! git -C "$REPO_ROOT" remote get-url "$GIT_REMOTE" >/dev/null 2>&1; then
  printf 'Git remote not found: %s\n' "$GIT_REMOTE" >&2
  exit 1
fi

get_remote_revision() {
  git -C "$REPO_ROOT" ls-remote --heads "$GIT_REMOTE" "refs/heads/$GIT_BRANCH" 2>/dev/null \
    | awk 'NR == 1 { print $1 }'
}

kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" >/dev/null
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" >/dev/null

BASELINE_REMOTE_REVISION="$(get_remote_revision || true)"
if [[ -z "$BASELINE_REMOTE_REVISION" ]]; then
  printf 'Could not read remote branch %s/%s. Check remote connectivity and credentials.\n' \
    "$GIT_REMOTE" "$GIT_BRANCH" >&2
  exit 1
fi

printf 'Waiting for a stable Healthy/Ready baseline on %s/%s.\n' "$GIT_REMOTE" "$GIT_BRANCH"
BASELINE_DEADLINE=$(( $(date +%s) + BASELINE_TIMEOUT_SECONDS ))
BASELINE_IMAGE=""
BASELINE_GENERATION=""
BASELINE_REPLICAS=""
BASELINE_ARGO_REVISION=""

while (( $(date +%s) < BASELINE_DEADLINE )); do
  CURRENT_REMOTE_REVISION="$(get_remote_revision || true)"
  if [[ -n "$CURRENT_REMOTE_REVISION" ]]; then
    BASELINE_REMOTE_REVISION="$CURRENT_REMOTE_REVISION"
  fi

  APP_JSON="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
  DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
  PODS_JSON="$(kubectl get pods --namespace "$APP_NAMESPACE" -l "$APP_SELECTOR" -o json)"
  ARGO_REVISION="$(jq -r '.status.sync.revision // ""' <<< "$APP_JSON")"
  ARGO_SYNC="$(jq -r '.status.sync.status // "Unknown"' <<< "$APP_JSON")"
  ARGO_HEALTH="$(jq -r '.status.health.status // "Unknown"' <<< "$APP_JSON")"
  GENERATION="$(jq -r '.metadata.generation // 0' <<< "$DEPLOYMENT_JSON")"
  OBSERVED_GENERATION="$(jq -r '.status.observedGeneration // 0' <<< "$DEPLOYMENT_JSON")"
  DESIRED_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$DEPLOYMENT_JSON")"
  UPDATED_REPLICAS="$(jq -r '.status.updatedReplicas // 0' <<< "$DEPLOYMENT_JSON")"
  AVAILABLE_REPLICAS="$(jq -r '.status.availableReplicas // 0' <<< "$DEPLOYMENT_JSON")"
  READY_PODS="$(jq '[.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$PODS_JSON")"

  if [[ "$ARGO_REVISION" == "$BASELINE_REMOTE_REVISION" \
    && "$ARGO_SYNC" == "Synced" && "$ARGO_HEALTH" == "Healthy" \
    && "$OBSERVED_GENERATION" == "$GENERATION" \
    && "$DESIRED_REPLICAS" -gt 0 \
    && "$UPDATED_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$AVAILABLE_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$READY_PODS" -eq "$DESIRED_REPLICAS" ]]; then
    BASELINE_ARGO_REVISION="$ARGO_REVISION"
    BASELINE_GENERATION="$GENERATION"
    BASELINE_REPLICAS="$DESIRED_REPLICAS"
    BASELINE_IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$DEPLOYMENT_JSON")"
    break
  fi
  sleep "$POLL_SECONDS"
done

if [[ -z "$BASELINE_IMAGE" ]]; then
  printf 'The current remote revision did not reach a Healthy/Ready baseline before timeout.\n' >&2
  exit 1
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RUN_LABEL"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"
METADATA_FILE="$RUN_DIR/metadata.txt"
TIMELINE_FILE="$RUN_DIR/failure-recovery-timeline.csv"

cat > "$METADATA_FILE" <<EOF
Run ID: $RUN_ID
Git remote: $GIT_REMOTE
Git branch: $GIT_BRANCH
Baseline remote revision: $BASELINE_REMOTE_REVISION
Baseline Argo CD revision: $BASELINE_ARGO_REVISION
Baseline Deployment generation: $BASELINE_GENERATION
Baseline image: $BASELINE_IMAGE
Baseline replicas: $BASELINE_REPLICAS
Argo CD Application: $ARGO_NAMESPACE/$ARGO_APPLICATION
Kubernetes Deployment: $APP_NAMESPACE/$DEPLOYMENT_NAME
Poll interval seconds: $POLL_SECONDS
Failure timeout seconds: $FAILURE_TIMEOUT_SECONDS
Recovery timeout seconds: $RECOVERY_TIMEOUT_SECONDS
Stable recovery samples: $STABLE_SAMPLES
Failure definition: selected app pod reports ErrImagePull or ImagePullBackOff
Recovery definition: Argo CD Synced/Healthy on recovery revision, baseline image restored, and all desired replicas Ready
EOF

kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml > "$RUN_DIR/argo-before.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml > "$RUN_DIR/deployment-before.yaml"

printf 'timestamp_utc,phase,remote_revision,argo_revision,argo_sync,argo_health,deployment_generation,deployment_image,desired_replicas,updated_replicas,available_replicas,pods_ready,pods_total,pods_with_pull_error\n' \
  > "$TIMELINE_FILE"

PHASE="waiting_for_failure"
FAILURE_REVISION=""
RECOVERY_REVISION=""
FAILURE_REVISION_SEEN_UTC=""
FAILURE_REVISION_SEEN_EPOCH=""
PULL_FAILURE_SEEN_UTC=""
PULL_FAILURE_SEEN_EPOCH=""
ARGO_DEGRADED_SEEN_UTC=""
RECOVERY_REVISION_SEEN_UTC=""
RECOVERY_REVISION_SEEN_EPOCH=""
RECOVERY_READY_UTC=""
RECOVERY_READY_EPOCH=""
STABLE_RECOVERY_COUNT=0

capture_sample() {
  local timestamp app_json deployment_json pods_json pull_failures
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  NOW_EPOCH="$(date +%s)"
  REMOTE_REVISION="$(get_remote_revision || true)"
  app_json="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
  deployment_json="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
  pods_json="$(kubectl get pods --namespace "$APP_NAMESPACE" -l "$APP_SELECTOR" -o json)"

  ARGO_REVISION="$(jq -r '.status.sync.revision // ""' <<< "$app_json")"
  ARGO_SYNC="$(jq -r '.status.sync.status // "Unknown"' <<< "$app_json")"
  ARGO_HEALTH="$(jq -r '.status.health.status // "Unknown"' <<< "$app_json")"
  DEPLOYMENT_GENERATION="$(jq -r '.metadata.generation // 0' <<< "$deployment_json")"
  OBSERVED_GENERATION="$(jq -r '.status.observedGeneration // 0' <<< "$deployment_json")"
  DEPLOYMENT_IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$deployment_json")"
  DESIRED_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$deployment_json")"
  UPDATED_REPLICAS="$(jq -r '.status.updatedReplicas // 0' <<< "$deployment_json")"
  AVAILABLE_REPLICAS="$(jq -r '.status.availableReplicas // 0' <<< "$deployment_json")"
  PODS_TOTAL="$(jq '.items | length' <<< "$pods_json")"
  PODS_READY="$(jq '[.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$pods_json")"
  PULL_FAILURES="$(jq -r '[.items[]? | .metadata.name as $pod | .status.containerStatuses[]? | select(.state.waiting.reason == "ErrImagePull" or .state.waiting.reason == "ImagePullBackOff") | "\($pod):\(.state.waiting.reason)"] | unique | join(";")' <<< "$pods_json")"

  jq -rn \
    --arg timestamp "$timestamp" \
    --arg phase "$PHASE" \
    --arg remote "$REMOTE_REVISION" \
    --arg argo "$ARGO_REVISION" \
    --arg sync "$ARGO_SYNC" \
    --arg health "$ARGO_HEALTH" \
    --arg generation "$DEPLOYMENT_GENERATION" \
    --arg image "$DEPLOYMENT_IMAGE" \
    --arg desired "$DESIRED_REPLICAS" \
    --arg updated "$UPDATED_REPLICAS" \
    --arg available "$AVAILABLE_REPLICAS" \
    --arg ready "$PODS_READY" \
    --arg total "$PODS_TOTAL" \
    --arg pull_failures "$PULL_FAILURES" \
    '[$timestamp,$phase,$remote,$argo,$sync,$health,$generation,$image,$desired,$updated,$available,$ready,$total,$pull_failures] | @csv' \
    >> "$TIMELINE_FILE"
}

kubectl get hpa "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml > "$RUN_DIR/hpa-before.yaml" 2>/dev/null || true
printf 'Watching for a bad image-tag revision. Push a unique nonexistent tag to %s/%s.\n' "$GIT_REMOTE" "$GIT_BRANCH"
printf 'RUN_ID=%s\nResults: %s\nKnown-good image to restore: %s\n' "$RUN_ID" "$RUN_DIR" "$BASELINE_IMAGE"

DEADLINE=$(( $(date +%s) + FAILURE_TIMEOUT_SECONDS ))
while (( $(date +%s) < DEADLINE )); do
  capture_sample

  if [[ -z "$FAILURE_REVISION" && -n "$REMOTE_REVISION" && "$REMOTE_REVISION" != "$BASELINE_REMOTE_REVISION" ]]; then
    FAILURE_REVISION="$REMOTE_REVISION"
    FAILURE_REVISION_SEEN_EPOCH="$NOW_EPOCH"
    FAILURE_REVISION_SEEN_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Failure revision first observed: %s at %s\n' "$FAILURE_REVISION" "$FAILURE_REVISION_SEEN_UTC" >> "$METADATA_FILE"
    printf 'Failure revision observed; waiting for a pod image-pull error.\n'
  fi

  if [[ -n "$FAILURE_REVISION" && -z "$PULL_FAILURE_SEEN_EPOCH" && -n "$PULL_FAILURES" ]]; then
    PULL_FAILURE_SEEN_EPOCH="$NOW_EPOCH"
    PULL_FAILURE_SEEN_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PHASE="waiting_for_recovery"
    printf 'Pod pull failure observed: %s at %s\n' "$PULL_FAILURES" "$PULL_FAILURE_SEEN_UTC"
    printf 'Restore the known-good image tag shown above and push the recovery revision now.\n'
    printf 'Pod pull failure UTC: %s\nPod pull failure state: %s\n' "$PULL_FAILURE_SEEN_UTC" "$PULL_FAILURES" >> "$METADATA_FILE"
  fi

  if [[ -n "$PULL_FAILURE_SEEN_EPOCH" && -z "$ARGO_DEGRADED_SEEN_UTC" \
    && "$ARGO_REVISION" == "$FAILURE_REVISION" && "$ARGO_HEALTH" == "Degraded" ]]; then
    ARGO_DEGRADED_SEEN_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Argo CD Degraded observed UTC: %s\n' "$ARGO_DEGRADED_SEEN_UTC" >> "$METADATA_FILE"
  fi

  if [[ -n "$PULL_FAILURE_SEEN_EPOCH" && -z "$RECOVERY_REVISION" \
    && -n "$REMOTE_REVISION" && "$REMOTE_REVISION" != "$FAILURE_REVISION" ]]; then
    RECOVERY_REVISION="$REMOTE_REVISION"
    RECOVERY_REVISION_SEEN_EPOCH="$NOW_EPOCH"
    RECOVERY_REVISION_SEEN_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    DEADLINE=$((NOW_EPOCH + RECOVERY_TIMEOUT_SECONDS))
    PHASE="waiting_for_recovery_health"
    printf 'Recovery revision first observed: %s at %s\n' "$RECOVERY_REVISION" "$RECOVERY_REVISION_SEEN_UTC" >> "$METADATA_FILE"
    printf 'Recovery revision observed; waiting for Healthy/Ready baseline.\n'
  fi

  if [[ -n "$RECOVERY_REVISION" \
    && "$REMOTE_REVISION" == "$RECOVERY_REVISION" \
    && "$ARGO_REVISION" == "$RECOVERY_REVISION" \
    && "$ARGO_SYNC" == "Synced" && "$ARGO_HEALTH" == "Healthy" \
    && "$OBSERVED_GENERATION" == "$DEPLOYMENT_GENERATION" \
    && "$DEPLOYMENT_GENERATION" -gt "$BASELINE_GENERATION" \
    && "$DEPLOYMENT_IMAGE" == "$BASELINE_IMAGE" \
    && "$DESIRED_REPLICAS" -eq "$BASELINE_REPLICAS" \
    && "$UPDATED_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$AVAILABLE_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$PODS_READY" -eq "$DESIRED_REPLICAS" \
    && -z "$PULL_FAILURES" ]]; then
    STABLE_RECOVERY_COUNT=$((STABLE_RECOVERY_COUNT + 1))
    if (( STABLE_RECOVERY_COUNT >= STABLE_SAMPLES )); then
      RECOVERY_READY_EPOCH="$NOW_EPOCH"
      RECOVERY_READY_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      break
    fi
  else
    STABLE_RECOVERY_COUNT=0
  fi

  sleep "$POLL_SECONDS"
done

if [[ -z "$FAILURE_REVISION" ]]; then
  printf 'No failure revision was observed before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Result: timeout waiting for failure revision.\n' >> "$METADATA_FILE"
  exit 1
fi
if [[ -z "$PULL_FAILURE_SEEN_EPOCH" ]]; then
  printf 'The failure revision was observed, but no pod pull error appeared before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Result: timeout waiting for ErrImagePull/ImagePullBackOff.\n' >> "$METADATA_FILE"
  exit 1
fi
if [[ -z "$RECOVERY_REVISION" ]]; then
  printf 'The pod pull error was observed, but no recovery revision arrived before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Result: timeout waiting for recovery revision.\n' >> "$METADATA_FILE"
  exit 1
fi
if [[ -z "$RECOVERY_READY_EPOCH" ]]; then
  printf 'The recovery revision was observed, but the baseline did not become Healthy/Ready before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Result: timeout waiting for stable Healthy/Ready recovery.\n' >> "$METADATA_FILE"
  exit 1
fi

FAILURE_DETECTION_SECONDS=$((PULL_FAILURE_SEEN_EPOCH - FAILURE_REVISION_SEEN_EPOCH))
RECOVERY_SECONDS=$((RECOVERY_READY_EPOCH - RECOVERY_REVISION_SEEN_EPOCH))
TOTAL_INCIDENT_SECONDS=$((RECOVERY_READY_EPOCH - FAILURE_REVISION_SEEN_EPOCH))
printf 'Failure detection seconds (revision observed to pod pull error): %s\n' "$FAILURE_DETECTION_SECONDS" >> "$METADATA_FILE"
printf 'Recovery seconds (recovery revision observed to stable Healthy/Ready): %s\n' "$RECOVERY_SECONDS" >> "$METADATA_FILE"
printf 'Total incident seconds (failure revision observed to stable recovery): %s\n' "$TOTAL_INCIDENT_SECONDS" >> "$METADATA_FILE"
printf 'Recovery Healthy/Ready UTC: %s\n' "$RECOVERY_READY_UTC" >> "$METADATA_FILE"
printf 'Timing resolution: up to %s seconds from polling interval\n' "$POLL_SECONDS" >> "$METADATA_FILE"

kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml > "$RUN_DIR/argo-after.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml > "$RUN_DIR/deployment-after.yaml"
kubectl get hpa "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml > "$RUN_DIR/hpa-after.yaml" 2>/dev/null || true

printf '\nFailure/recovery measurement complete. Results: %s\n' "$RUN_DIR"
printf 'Failure detection: %ss; recovery: %ss; total incident: %ss\n' \
  "$FAILURE_DETECTION_SECONDS" "$RECOVERY_SECONDS" "$TOTAL_INCIDENT_SECONDS"