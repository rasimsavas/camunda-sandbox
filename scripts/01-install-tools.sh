#!/bin/bash
set -euo pipefail

# 01-install-tools.sh — Install kind, kubectl, helm, yq, jq to ~/.local/bin
# Run this first. Requires curl. Docker must already be installed and running.

source "$(dirname "$0")/../lib/common.sh"

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

install_if_missing() {
    local name="$1"
    local url="$2"
    local file="${3:-$name}"

    if command -v "$name" >/dev/null 2>&1; then
        echo "  $name: already installed ($(command -v "$name"))"
        return 0
    fi

    echo "  Installing $name..."
    curl -sL "$url" -o "$LOCAL_BIN/$file"
    chmod +x "$LOCAL_BIN/$file"
    [ "$file" != "$name" ] && mv "$LOCAL_BIN/$file" "$LOCAL_BIN/$name" 2>/dev/null || true
    echo "  $name: installed at $LOCAL_BIN/$name"
}

export PATH="$LOCAL_BIN:$PATH"

echo "=== Installing tools to $LOCAL_BIN ==="

install_if_missing kind \
    "https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-amd64" \
    "kind"

install_if_missing kubectl \
    "https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl" \
    "kubectl"

install_if_missing helm \
    "https://get.helm.sh/helm-v4.2.0-linux-amd64.tar.gz" \
    "helm-v4.2.0-linux-amd64.tar.gz"

if ! command -v helm >/dev/null 2>&1; then
    echo "  Installing helm from archive..."
    tar xzf "$LOCAL_BIN/helm-v4.2.0-linux-amd64.tar.gz" -C /tmp/ linux-amd64/helm
    mv /tmp/linux-amd64/helm "$LOCAL_BIN/helm"
    chmod +x "$LOCAL_BIN/helm"
    rm "$LOCAL_BIN/helm-v4.2.0-linux-amd64.tar.gz"
    echo "  helm: installed at $LOCAL_BIN/helm"
fi

install_if_missing yq \
    "https://github.com/mikefarah/yq/releases/download/v4.53.2/yq_linux_amd64" \
    "yq"

if ! command -v jq >/dev/null 2>&1; then
    echo "  Installing jq..."
    curl -sL "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64" -o "$LOCAL_BIN/jq"
    chmod +x "$LOCAL_BIN/jq"
    echo "  jq: installed at $LOCAL_BIN/jq"
fi

echo ""
echo "=== Verifying tools ==="
for cmd in kind kubectl helm yq jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  $cmd: OK ($(command -v "$cmd"))"
    else
        echo "  $cmd: MISSING — add $LOCAL_BIN to your PATH"
    fi
done

echo ""
echo "Ensure $LOCAL_BIN is in your PATH:"
echo "  export PATH=\"$LOCAL_BIN:\$PATH\""
