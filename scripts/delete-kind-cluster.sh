#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/jdk/bin:$HOME/.local/apache-maven/bin:$PATH"

kind delete cluster --name thesis-cluster || true