#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:?HOME must be set}"
LOCAL_ROOT="$HOME_DIR/.local"
BIN_DIR="$LOCAL_ROOT/bin"
mkdir -p "$BIN_DIR"

for command in curl find grep tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  printf 'This bootstrap script currently supports Linux x86_64 only.\n' >&2
  exit 1
fi

function install_java() {
  if [ -x "$LOCAL_ROOT/jdk/bin/java" ]; then
    echo "Java 21 already installed at $LOCAL_ROOT/jdk"
    return
  fi

  echo "Installing Temurin JDK 21 into $LOCAL_ROOT/jdk"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' RETURN

  curl -fsSL "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse" -o "$tmp_dir/jdk.tar.gz"
  tar -xzf "$tmp_dir/jdk.tar.gz" -C "$tmp_dir"
  local extracted_dir
  extracted_dir=$(find "$tmp_dir" -maxdepth 1 -mindepth 1 -type d -name 'jdk-*' | head -n 1)
  if [ -z "$extracted_dir" ]; then
    echo "Unable to find extracted JDK directory" >&2
    exit 1
  fi

  mv "$extracted_dir" "$LOCAL_ROOT/jdk"
}

function install_maven() {
  if [ -x "$LOCAL_ROOT/apache-maven/bin/mvn" ]; then
    echo "Maven already installed at $LOCAL_ROOT/apache-maven"
    return
  fi

  echo "Installing Maven into $LOCAL_ROOT/apache-maven"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' RETURN

  curl -fsSL "https://dlcdn.apache.org/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.tar.gz" -o "$tmp_dir/maven.tar.gz"
  tar -xzf "$tmp_dir/maven.tar.gz" -C "$tmp_dir"
  local extracted_dir
  extracted_dir=$(find "$tmp_dir" -maxdepth 1 -mindepth 1 -type d -name 'apache-maven-*' | head -n 1)
  if [ -z "$extracted_dir" ]; then
    echo "Unable to find extracted Maven directory" >&2
    exit 1
  fi

  mv "$extracted_dir" "$LOCAL_ROOT/apache-maven"
}

function install_kind() {
  if [ -x "$BIN_DIR/kind" ]; then
    echo "kind already installed"
    return
  fi

  echo "Installing kind into $BIN_DIR"
  curl -fsSL "https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64" -o "$BIN_DIR/kind"
  chmod +x "$BIN_DIR/kind"
}

function install_kubectl() {
  if [ -x "$BIN_DIR/kubectl" ]; then
    echo "kubectl already installed"
    return
  fi

  echo "Installing kubectl into $BIN_DIR"
  curl -fsSL "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" -o "$BIN_DIR/kubectl"
  chmod +x "$BIN_DIR/kubectl"
}

function install_helm() {
  if [ -x "$BIN_DIR/helm" ]; then
    echo "Helm already installed"
    return
  fi

  echo "Installing Helm into $BIN_DIR"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' RETURN

  curl -fsSL "https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz" -o "$tmp_dir/helm.tar.gz"
  tar -xzf "$tmp_dir/helm.tar.gz" -C "$tmp_dir"
  cp "$tmp_dir/linux-amd64/helm" "$BIN_DIR/helm"
  chmod +x "$BIN_DIR/helm"
}

install_java
install_maven
install_kind
install_kubectl
install_helm

echo
printf 'Local toolchain installed successfully.\n'
printf 'For Bash or Zsh, run:\n'
printf '  export JAVA_HOME="$HOME/.local/jdk"\n'
printf '  export PATH="$HOME/.local/jdk/bin:$HOME/.local/apache-maven/bin:$HOME/.local/bin:$PATH"\n'
printf 'For Fish, run:\n'
printf '  set -gx PATH "$HOME/.local/jdk/bin" "$HOME/.local/apache-maven/bin" "$HOME/.local/bin" $PATH\n'
printf 'Then verify the app with:\n'
printf '  cd %s/apps/pipeline-pilot && mvn test\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"