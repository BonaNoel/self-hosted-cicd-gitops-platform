#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! docker info >/dev/null 2>&1; then
  printf 'Cannot access Docker from this shell.\n' >&2
  printf 'Make sure Docker Desktop is running and WSL integration is enabled for this distro.\n' >&2
  printf 'If Docker is running, check your permissions on /var/run/docker.sock.\n' >&2
  exit 1
fi

docker compose --env-file .env.example down