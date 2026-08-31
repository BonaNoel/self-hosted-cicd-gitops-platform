#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/jdk/bin:$HOME/.local/apache-maven/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

kind create cluster --name thesis-cluster --config "$REPO_ROOT/kind/cluster-config.yaml"

echo
printf 'Kind cluster created.\n'
printf 'Use: kubectl cluster-info --context kind-thesis-cluster\n'
