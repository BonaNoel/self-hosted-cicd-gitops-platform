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
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
BASELINE_TIMEOUT_SECONDS="${BASELINE_TIMEOUT_SECONDS:-600}"
RUN_LABEL="${RUN_LABEL:-deployment}"
RESULTS_DIR="${RESULTS_DIR:-$HOME/thesis-writing/meresek}"

usage() {
  cat <<'EOF'
Measure remote-commit detection to healthy Kubernetes deployment time.

Start this script before pushing an application change to the watched Gitea
branch. It polls the remote branch, Argo CD Application, Deployment, and pods.

Environment variables:
  GIT_REMOTE          Git remote name (default: gitea)
  GIT_BRANCH          Branch watched by Argo CD (default: development)
  ARGO_NAMESPACE      Argo CD namespace (default: argocd)
  ARGO_APPLICATION    Argo CD Application name (default: pipeline-pilot)
  APP_NAMESPACE       Workload namespace (default: dev)
  DEPLOYMENT_NAME     Kubernetes Deployment name (default: pipeline-pilot)
  POLL_SECONDS        Poll interval (default: 2)
  TIMEOUT_SECONDS     Timeout waiting for a new remote revision (default: 1200)
  BASELINE_TIMEOUT_SECONDS Timeout waiting for the current deployment to settle (default: 600)
  RUN_LABEL           Label in result directory (default: deployment)
  RESULTS_DIR         Output root (default: ~/thesis-writing/meresek)

Example:
  RUN_LABEL=trial-01 bash scripts/run-deployment-lead-time-measurement.sh

After the script reports that it is watching, push a commit that changes
apps/pipeline-pilot/. It does not push commits or modify the repository.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for command in git kubectl jq date; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if ! [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || (( POLL_SECONDS < 1 )); then
  printf 'POLL_SECONDS must be a positive integer.\n' >&2
  exit 2
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( TIMEOUT_SECONDS < 1 )); then
  printf 'TIMEOUT_SECONDS must be a positive integer.\n' >&2
  exit 2
fi
if ! [[ "$BASELINE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( BASELINE_TIMEOUT_SECONDS < 1 )); then
  printf 'BASELINE_TIMEOUT_SECONDS must be a positive integer.\n' >&2
  exit 2
fi
if ! [[ "$RUN_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'RUN_LABEL may contain only letters, numbers, dots, underscores, and hyphens.\n' >&2
  exit 2
fi

if ! git -C "$REPO_ROOT" remote get-url "$GIT_REMOTE" >/dev/null 2>&1; then
  printf 'Git remote not found: %s\n' "$GIT_REMOTE" >&2
  exit 1
fi
kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" >/dev/null
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" >/dev/null
BASELINE_DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
BASELINE_DEPLOYMENT_GENERATION="$(jq -r '.metadata.generation // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
BASELINE_IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$BASELINE_DEPLOYMENT_JSON")"

get_remote_revision() {
  git -C "$REPO_ROOT" ls-remote --heads "$GIT_REMOTE" "refs/heads/$GIT_BRANCH" 2>/dev/null \
    | awk 'NR == 1 { print $1 }'
}

BASELINE_REMOTE_REVISION="$(get_remote_revision || true)"
if [[ -z "$BASELINE_REMOTE_REVISION" ]]; then
  printf 'Could not read remote branch %s/%s. Check remote connectivity and credentials.\n' \
    "$GIT_REMOTE" "$GIT_BRANCH" >&2
  exit 1
fi

printf 'Waiting for the current Gitea revision to be fully deployed before measurement.\n'
BASELINE_DEADLINE=$(( $(date +%s) + BASELINE_TIMEOUT_SECONDS ))
BASELINE_ARGO_REVISION=""
BASELINE_DEPLOYMENT_GENERATION=""
BASELINE_IMAGE=""

while (( $(date +%s) < BASELINE_DEADLINE )); do
  CURRENT_REMOTE_REVISION="$(get_remote_revision || true)"
  if [[ -n "$CURRENT_REMOTE_REVISION" ]]; then
    BASELINE_REMOTE_REVISION="$CURRENT_REMOTE_REVISION"
  fi

  BASELINE_APP_JSON="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
  CURRENT_ARGO_REVISION="$(jq -r '.status.sync.revision // ""' <<< "$BASELINE_APP_JSON")"
  CURRENT_SYNC="$(jq -r '.status.sync.status // "Unknown"' <<< "$BASELINE_APP_JSON")"
  CURRENT_HEALTH="$(jq -r '.status.health.status // "Unknown"' <<< "$BASELINE_APP_JSON")"
  BASELINE_DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
  CURRENT_GENERATION="$(jq -r '.metadata.generation // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
  CURRENT_OBSERVED_GENERATION="$(jq -r '.status.observedGeneration // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
  CURRENT_DESIRED_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
  CURRENT_UPDATED_REPLICAS="$(jq -r '.status.updatedReplicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
  CURRENT_AVAILABLE_REPLICAS="$(jq -r '.status.availableReplicas // 0' <<< "$BASELINE_DEPLOYMENT_JSON")"
  CURRENT_PODS_JSON="$(kubectl get pods --namespace "$APP_NAMESPACE" -l app.kubernetes.io/instance=pipeline-pilot,app.kubernetes.io/name=pipeline-pilot -o json)"
  CURRENT_PODS_READY="$(jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$CURRENT_PODS_JSON")"

  if [[ "$CURRENT_ARGO_REVISION" == "$BASELINE_REMOTE_REVISION" \
    && "$CURRENT_SYNC" == "Synced" && "$CURRENT_HEALTH" == "Healthy" \
    && "$CURRENT_OBSERVED_GENERATION" == "$CURRENT_GENERATION" \
    && "$CURRENT_DESIRED_REPLICAS" -gt 0 \
    && "$CURRENT_UPDATED_REPLICAS" -eq "$CURRENT_DESIRED_REPLICAS" \
    && "$CURRENT_AVAILABLE_REPLICAS" -eq "$CURRENT_DESIRED_REPLICAS" \
    && "$CURRENT_PODS_READY" -eq "$CURRENT_DESIRED_REPLICAS" ]]; then
    BASELINE_ARGO_REVISION="$CURRENT_ARGO_REVISION"
    BASELINE_DEPLOYMENT_GENERATION="$CURRENT_GENERATION"
    BASELINE_IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$BASELINE_DEPLOYMENT_JSON")"
    break
  fi
  sleep "$POLL_SECONDS"
done

if [[ -z "$BASELINE_ARGO_REVISION" ]]; then
  printf 'The current remote revision did not reach a healthy, fully ready baseline before timeout.\n' >&2
  exit 1
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RUN_LABEL"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR/screenshots"

METADATA_FILE="$RUN_DIR/metadata.txt"
TIMELINE_FILE="$RUN_DIR/deployment-timeline.csv"

cat > "$METADATA_FILE" <<EOF
Run ID: $RUN_ID
Git remote: $GIT_REMOTE
Git branch: $GIT_BRANCH
Baseline remote revision: $BASELINE_REMOTE_REVISION
Baseline Argo CD revision: $BASELINE_ARGO_REVISION
Baseline Deployment generation: $BASELINE_DEPLOYMENT_GENERATION
Baseline image: $BASELINE_IMAGE
Argo CD Application: $ARGO_NAMESPACE/$ARGO_APPLICATION
Kubernetes Deployment: $APP_NAMESPACE/$DEPLOYMENT_NAME
Poll interval seconds: $POLL_SECONDS
Timeout seconds: $TIMEOUT_SECONDS
Start definition: first poll that observes a changed remote branch revision
Ready definition: Argo CD Synced and Healthy, image and Deployment generation changed, Deployment updated/available replicas equal desired, and all selected application pods Ready

EOF

kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml \
  > "$RUN_DIR/argo-before.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/deployment-before.yaml"

printf 'timestamp_utc,remote_revision,argo_revision,argo_sync,argo_health,deployment_generation,observed_generation,deployment_generation_changed,image_changed,desired_replicas,updated_replicas,available_replicas,pods_ready,pods_total,image\n' \
  > "$TIMELINE_FILE"

START_EPOCH=""
REMOTE_CHANGE_SEEN_AT=""
REMOTE_CHANGE_REVISION=""
ARGO_REVISION_SEEN_AT=""
READY_SEEN_AT=""
READY_EPOCH=""
LAST_REMOTE_REVISION="$BASELINE_REMOTE_REVISION"
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

printf 'Watching for a new commit. Push an application code change to %s/%s now.\n' \
  "$GIT_REMOTE" "$GIT_BRANCH"
printf 'RUN_ID=%s\nResults: %s\n' "$RUN_ID" "$RUN_DIR"
printf 'Save dashboard screenshots in the screenshots/ directory.\n'

while (( $(date +%s) < DEADLINE )); do
  NOW_EPOCH="$(date +%s)"
  NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  REMOTE_REVISION="$(get_remote_revision || true)"

  if [[ -n "$REMOTE_REVISION" && "$REMOTE_REVISION" != "$LAST_REMOTE_REVISION" ]]; then
    LAST_REMOTE_REVISION="$REMOTE_REVISION"
    if [[ -z "$START_EPOCH" ]]; then
      START_EPOCH="$NOW_EPOCH"
      REMOTE_CHANGE_SEEN_AT="$NOW_UTC"
      REMOTE_CHANGE_REVISION="$REMOTE_REVISION"
      printf 'Remote change detected: %s (%s)\n' "$REMOTE_CHANGE_REVISION" "$REMOTE_CHANGE_SEEN_AT"
    fi
  fi

  ARGO_JSON="$(kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o json)"
  ARGO_REVISION="$(jq -r '.status.sync.revision // ""' <<< "$ARGO_JSON")"
  ARGO_SYNC="$(jq -r '.status.sync.status // "Unknown"' <<< "$ARGO_JSON")"
  ARGO_HEALTH="$(jq -r '.status.health.status // "Unknown"' <<< "$ARGO_JSON")"
  DEPLOYMENT_JSON="$(kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o json)"
  DEPLOYMENT_GENERATION="$(jq -r '.metadata.generation // 0' <<< "$DEPLOYMENT_JSON")"
  OBSERVED_GENERATION="$(jq -r '.status.observedGeneration // 0' <<< "$DEPLOYMENT_JSON")"
  DESIRED_REPLICAS="$(jq -r '.spec.replicas // 0' <<< "$DEPLOYMENT_JSON")"
  UPDATED_REPLICAS="$(jq -r '.status.updatedReplicas // 0' <<< "$DEPLOYMENT_JSON")"
  AVAILABLE_REPLICAS="$(jq -r '.status.availableReplicas // 0' <<< "$DEPLOYMENT_JSON")"
  IMAGE="$(jq -r '.spec.template.spec.containers[0].image // "unknown"' <<< "$DEPLOYMENT_JSON")"
  if [[ "$DEPLOYMENT_GENERATION" != "$BASELINE_DEPLOYMENT_GENERATION" ]]; then
    DEPLOYMENT_GENERATION_CHANGED=true
  else
    DEPLOYMENT_GENERATION_CHANGED=false
  fi
  if [[ "$IMAGE" != "$BASELINE_IMAGE" ]]; then
    IMAGE_CHANGED=true
  else
    IMAGE_CHANGED=false
  fi
  PODS_JSON="$(kubectl get pods --namespace "$APP_NAMESPACE" -l app.kubernetes.io/instance=pipeline-pilot,app.kubernetes.io/name=pipeline-pilot -o json)"
  PODS_TOTAL="$(jq '.items | length' <<< "$PODS_JSON")"
  PODS_READY="$(jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' <<< "$PODS_JSON")"

  if [[ -n "$START_EPOCH" && -z "$ARGO_REVISION_SEEN_AT" && -n "$ARGO_REVISION" && "$ARGO_REVISION" != "$BASELINE_ARGO_REVISION" ]]; then
    ARGO_REVISION_SEEN_AT="$NOW_UTC"
  fi

  jq -rn \
    --arg timestamp "$NOW_UTC" \
    --arg remote "$REMOTE_REVISION" \
    --arg argo "$ARGO_REVISION" \
    --arg sync "$ARGO_SYNC" \
    --arg health "$ARGO_HEALTH" \
    --arg generation "$DEPLOYMENT_GENERATION" \
    --arg observed "$OBSERVED_GENERATION" \
    --arg generation_changed "$DEPLOYMENT_GENERATION_CHANGED" \
    --arg image_changed "$IMAGE_CHANGED" \
    --arg desired "$DESIRED_REPLICAS" \
    --arg updated "$UPDATED_REPLICAS" \
    --arg available "$AVAILABLE_REPLICAS" \
    --arg ready "$PODS_READY" \
    --arg total "$PODS_TOTAL" \
    --arg image "$IMAGE" \
    '[$timestamp,$remote,$argo,$sync,$health,$generation,$observed,$generation_changed,$image_changed,$desired,$updated,$available,$ready,$total,$image] | @csv' \
    >> "$TIMELINE_FILE"

  if [[ -n "$START_EPOCH" && "$ARGO_REVISION" != "$BASELINE_ARGO_REVISION" \
    && "$DEPLOYMENT_GENERATION_CHANGED" == "true" && "$IMAGE_CHANGED" == "true" \
    && "$ARGO_SYNC" == "Synced" && "$ARGO_HEALTH" == "Healthy" \
    && "$OBSERVED_GENERATION" == "$DEPLOYMENT_GENERATION" \
    && "$DESIRED_REPLICAS" -gt 0 \
    && "$UPDATED_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$AVAILABLE_REPLICAS" -eq "$DESIRED_REPLICAS" \
    && "$PODS_READY" -eq "$DESIRED_REPLICAS" ]]; then
    READY_EPOCH="$NOW_EPOCH"
    READY_SEEN_AT="$NOW_UTC"
    break
  fi

  sleep "$POLL_SECONDS"
done

if [[ -z "$START_EPOCH" ]]; then
  printf 'No new commit was detected before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Result: timeout before a remote branch change was observed.\n' >> "$METADATA_FILE"
  exit 1
fi

if [[ -z "$READY_EPOCH" ]]; then
  printf 'The commit was detected, but no changed image reached a Healthy/Ready rollout before timeout. Results: %s\n' "$RUN_DIR" >&2
  printf 'Remote revision observed: %s at %s\n' "$REMOTE_CHANGE_REVISION" "$REMOTE_CHANGE_SEEN_AT" >> "$METADATA_FILE"
  printf 'Argo revision first observed: %s\n' "${ARGO_REVISION_SEEN_AT:-not observed}" >> "$METADATA_FILE"
  printf 'Result: timeout waiting for healthy and ready deployment.\n' >> "$METADATA_FILE"
  kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml \
    > "$RUN_DIR/argo-after-timeout.yaml"
  kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml \
    > "$RUN_DIR/deployment-after-timeout.yaml"
  exit 1
fi

LEAD_TIME_SECONDS=$((READY_EPOCH - START_EPOCH))
printf 'Remote change first seen UTC: %s\n' "$REMOTE_CHANGE_SEEN_AT" >> "$METADATA_FILE"
printf 'Remote revision first seen: %s\n' "$REMOTE_CHANGE_REVISION" >> "$METADATA_FILE"
printf 'Argo revision first observed UTC: %s\n' "$ARGO_REVISION_SEEN_AT" >> "$METADATA_FILE"
printf 'Deployment Healthy and all desired pods Ready UTC: %s\n' "$READY_SEEN_AT" >> "$METADATA_FILE"
printf 'Observed lead time seconds: %s\n' "$LEAD_TIME_SECONDS" >> "$METADATA_FILE"
printf 'Timing resolution: up to %s seconds from polling interval\n' "$POLL_SECONDS" >> "$METADATA_FILE"

kubectl get application "$ARGO_APPLICATION" --namespace "$ARGO_NAMESPACE" -o yaml \
  > "$RUN_DIR/argo-after.yaml"
kubectl get deployment "$DEPLOYMENT_NAME" --namespace "$APP_NAMESPACE" -o yaml \
  > "$RUN_DIR/deployment-after.yaml"

printf '\nDeployment measurement complete.\n'
printf 'Remote change first observed: %s\n' "$REMOTE_CHANGE_SEEN_AT"
printf 'Argo CD Healthy and all desired pods Ready: %s\n' "$READY_SEEN_AT"
printf 'Observed lead time: %s seconds (polling resolution: up to %s s)\n' \
  "$LEAD_TIME_SECONDS" "$POLL_SECONDS"
printf 'Results: %s\n' "$RUN_DIR"
printf 'Files: metadata.txt, deployment-timeline.csv, Argo CD and Deployment snapshots, screenshots/\n'
