#!/bin/bash
set -euo pipefail

# 04-deploy-camunda.sh — Create identity secrets + deploy Camunda via Helm
# Prerequisites: 03-deploy-operators.sh completed, helm in PATH

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl
require_cmd helm

# --- Identity secrets ---
echo "=== Creating camunda-credentials secret ==="
if kubectl get secret camunda-credentials -n "$CAMUNDA_NAMESPACE" >/dev/null 2>&1; then
    echo "  camunda-credentials already exists."
else
    kubectl create secret generic camunda-credentials \
        --namespace "$CAMUNDA_NAMESPACE" \
        --from-literal=identity-connectors-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-console-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-webmodeler-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-orchestration-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-optimize-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-admin-client-token="$(openssl rand -hex 16)" \
        --from-literal=identity-first-user-password="$(openssl rand -hex 16)" \
        --from-literal=webmodeler-pusher-app-secret="$(openssl rand -hex 16)" \
        --from-literal=webmodeler-pusher-app-key="$(openssl rand -hex 16)" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "  camunda-credentials created."
fi

# --- Helm deploy ---
echo ""
echo "=== Deploying Camunda Platform (chart v${CAMUNDA_HELM_CHART_VERSION}, ${SECONDARY_STORAGE} mode) ==="

COMMON_VALUES=(
    --values "$HELM_VALUES_DIR/camunda-keycloak-no-domain.yml"
    --values "$HELM_VALUES_DIR/camunda-identity-pg.yml"
    --values "$HELM_VALUES_DIR/camunda-webmodeler-pg.yml"
    --values "$HELM_VALUES_DIR/values-no-domain.yml"
)

if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
    COMMON_VALUES+=(--values "$HELM_VALUES_DIR/camunda-rdbms.yml")
fi

LAN_VALUES_FILE=""
if [ -n "$CAMUNDA_LAN_IP" ] && [ "$CAMUNDA_LAN_IP" != "127.0.0.1" ] && [ "$CAMUNDA_LAN_IP" != "localhost" ]; then
    echo "=== LAN mode enabled (LAN IP: ${CAMUNDA_LAN_IP}) ==="
    echo "  Browser-facing URLs will use 'keycloak-service' hostname (resolves to ${CAMUNDA_LAN_IP} from LAN)."
    COMMON_VALUES+=(--values "$HELM_VALUES_DIR/camunda-lan.yml")
fi

CAMUNDA_REPO="${CAMUNDA_REPO:-camunda}"
CAMUNDA_CHART="${CAMUNDA_CHART:-camunda-platform}"

helm repo add "$CAMUNDA_REPO" https://helm.camunda.io 2>/dev/null || true
helm repo update "$CAMUNDA_REPO"

helm upgrade --install "$CAMUNDA_RELEASE_NAME" \
    "$CAMUNDA_REPO/$CAMUNDA_CHART" \
    --version "$CAMUNDA_HELM_CHART_VERSION" \
    --namespace "$CAMUNDA_NAMESPACE" \
    "${COMMON_VALUES[@]}"

echo ""
echo "=== Waiting for all pods to be Ready ==="
wait_for_pods "$CAMUNDA_NAMESPACE" 900

echo ""
echo "Camunda Platform deployed successfully."
