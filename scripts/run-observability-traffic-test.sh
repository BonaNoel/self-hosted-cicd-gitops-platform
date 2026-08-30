#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="dev"
JOB_NAME="pipeline-pilot-traffic"
REQUESTS="${REQUESTS:-30}"
CPU_MILLIS="${CPU_MILLIS:-100}"
IO_MILLIS="${IO_MILLIS:-25}"
COMPLEXITY="${COMPLEXITY:-5000}"
PAUSE_SECONDS="${PAUSE_SECONDS:-1}"

validate_non_negative_integer() {
	local name="$1"
	local value="$2"

	if ! [[ "$value" =~ ^[0-9]+$ ]]; then
		printf '%s must be a non-negative integer; got %s\n' "$name" "$value" >&2
		exit 2
	fi
}

validate_non_negative_integer REQUESTS "$REQUESTS"
validate_non_negative_integer CPU_MILLIS "$CPU_MILLIS"
validate_non_negative_integer IO_MILLIS "$IO_MILLIS"
validate_non_negative_integer COMPLEXITY "$COMPLEXITY"
validate_non_negative_integer PAUSE_SECONDS "$PAUSE_SECONDS"

if (( REQUESTS < 1 )); then
	printf 'REQUESTS must be at least 1; got %s\n' "$REQUESTS" >&2
	exit 2
fi

if (( COMPLEXITY < 100 )); then
	printf 'COMPLEXITY must be at least 100; got %s\n' "$COMPLEXITY" >&2
	exit 2
fi

kubectl delete job "$JOB_NAME" --namespace "$NAMESPACE" --ignore-not-found
kubectl create --dry-run=client -o yaml -f "$REPO_ROOT/observability/pipeline-pilot-traffic-job.yaml" \
	| kubectl set env --local -f - -o yaml \
		"REQUESTS=$REQUESTS" \
		"CPU_MILLIS=$CPU_MILLIS" \
		"IO_MILLIS=$IO_MILLIS" \
		"COMPLEXITY=$COMPLEXITY" \
		"PAUSE_SECONDS=$PAUSE_SECONDS" \
	| kubectl apply -f -
kubectl wait --for=condition=complete "job/$JOB_NAME" --namespace "$NAMESPACE" --timeout=2m
kubectl logs "job/$JOB_NAME" --namespace "$NAMESPACE"