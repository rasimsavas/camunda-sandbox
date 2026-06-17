#!/bin/bash
set -euo pipefail

# 02-create-cluster.sh — Create Kind cluster + camunda namespace + /etc/hosts entry
# Prerequisites: Docker running, kind/kubectl in PATH

source "$(dirname "$0")/../lib/common.sh"

require_cmd kind
require_cmd kubectl

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Kind cluster '$CLUSTER_NAME' already exists."
else
    echo "=== Creating Kind cluster: $CLUSTER_NAME ==="
    kind create cluster --config "$CONFIGS_DIR/kind-cluster.yaml"
fi

echo ""
echo "=== Waiting for nodes to be Ready ==="
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o wide

echo ""
echo "=== Creating namespace: $CAMUNDA_NAMESPACE ==="
kubectl create namespace "$CAMUNDA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Adding /etc/hosts entries for keycloak-service ==="
if grep -q "^127\.0\.0\.1[[:space:]]\{1,\}keycloak-service$" /etc/hosts 2>/dev/null; then
    echo "  127.0.0.1 keycloak-service already exists."
else
    echo "  Adding: 127.0.0.1  keycloak-service (requires sudo)"
    echo "127.0.0.1  keycloak-service" | sudo tee -a /etc/hosts > /dev/null
    echo "  Added."
fi

if [ -n "$CAMUNDA_LAN_IP" ]; then
    if grep -q "^${CAMUNDA_LAN_IP}[[:space:]]\{1,\}keycloak-service$" /etc/hosts 2>/dev/null; then
        echo "  ${CAMUNDA_LAN_IP} keycloak-service already exists."
    else
        echo "  Adding: ${CAMUNDA_LAN_IP}  keycloak-service (requires sudo)"
        echo "${CAMUNDA_LAN_IP}  keycloak-service" | sudo tee -a /etc/hosts > /dev/null
        echo "  Added."
    fi
fi

echo ""
echo "Cluster ready."
