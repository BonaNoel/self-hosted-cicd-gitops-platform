#!/usr/bin/env bash
set -euo pipefail

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/jdk}"
export M2_HOME="${M2_HOME:-$HOME/.local/apache-maven}"
export PATH="$JAVA_HOME/bin:$M2_HOME/bin:$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT/apps/pipeline-pilot"
mvn spring-boot:run