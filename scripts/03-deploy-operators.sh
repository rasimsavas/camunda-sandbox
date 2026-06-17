#!/bin/bash
set -euo pipefail

# 03-deploy-operators.sh — Deploy CNPG operator, PG clusters, Keycloak operator + instance
# Prerequisites: 02-create-cluster.sh completed, yq in PATH

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl
require_cmd yq

# --- CloudNativePG operator ---
# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.28.1"
CNPG_MANIFEST_URL="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-${CNPG_VERSION}.yaml"

echo "=== Deploying CloudNativePG operator v${CNPG_VERSION} ==="
if kubectl get deployment cnpg-controller-manager -n cnpg-system >/dev/null 2>&1; then
    echo "  CNPG operator already installed."
else
    kubectl apply -n cnpg-system --server-side -f "${CNPG_MANIFEST_URL}"
    kubectl rollout status deployment cnpg-controller-manager -n cnpg-system --timeout=300s
    echo "  CNPG operator deployed."
fi

# --- PostgreSQL secrets ---
echo ""
echo "=== Creating PostgreSQL secrets ==="
create_or_get_secret() {
    local secret_name="$1" username="$2"
    if kubectl get secret "$secret_name" -n "$CAMUNDA_NAMESPACE" >/dev/null 2>&1; then
        echo "  $secret_name: already exists"
        return 0
    fi
    local password
    password=$(openssl rand -base64 18)
    kubectl create secret generic "$secret_name" -n "$CAMUNDA_NAMESPACE" \
        --from-literal=username="$username" \
        --from-literal=password="$password" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "  $secret_name: created"
}

for cluster in identity keycloak webmodeler; do
    create_or_get_secret "pg-${cluster}-superuser-secret" "root"
    create_or_get_secret "pg-${cluster}-secret" "$cluster"
done
create_or_get_secret "pg-camunda-superuser-secret" "root"
create_or_get_secret "pg-camunda-secret" "camunda"

# --- PostgreSQL clusters ---
echo ""
echo "=== Deploying PostgreSQL clusters ==="
kubectl apply --server-side -f "$CONFIGS_DIR/pg-clusters.yml" -n "$CAMUNDA_NAMESPACE"
for cluster in pg-identity pg-keycloak pg-webmodeler; do
    echo "  Waiting for $cluster..."
    kubectl wait --for=condition=Ready --timeout=600s cluster "$cluster" -n "$CAMUNDA_NAMESPACE"
done

if [[ "$SECONDARY_STORAGE" == "postgres" ]]; then
    echo ""
    echo "=== Deploying orchestration PG cluster (RDBMS mode) ==="
    kubectl apply --server-side -f "$CONFIGS_DIR/pg-orchestration-cluster.yml" -n "$CAMUNDA_NAMESPACE"
    kubectl wait --for=condition=Ready --timeout=600s cluster pg-camunda -n "$CAMUNDA_NAMESPACE"
else
    echo "  Skipping orchestration PG cluster (SECONDARY_STORAGE=$SECONDARY_STORAGE)"
fi

# --- Keycloak operator ---
# renovate: datasource=docker depName=camunda/keycloak versioning=regex:^quay-optimized-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
KEYCLOAK_VERSION="26.5.7"

echo ""
echo "=== Deploying Keycloak operator ==="
if kubectl get deployment keycloak-operator -n "$CAMUNDA_NAMESPACE" >/dev/null 2>&1; then
    echo "  Keycloak operator already installed."
else
    kubectl apply --server-side -f "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloaks.k8s.keycloak.org-v1.yml"
    kubectl apply --server-side -f "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml"
    kubectl apply -n "$CAMUNDA_NAMESPACE" --server-side -f "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${KEYCLOAK_VERSION}/kubernetes/kubernetes.yml"
    kubectl wait --for=condition=available --timeout=300s deployment/keycloak-operator -n "$CAMUNDA_NAMESPACE"
    echo "  Keycloak operator deployed."
fi

# --- Keycloak instance ---
echo ""
echo "=== Deploying Keycloak instance ==="
kubectl apply -f "$CONFIGS_DIR/keycloak-instance.yml" -n "$CAMUNDA_NAMESPACE"
kubectl wait --for=condition=Ready --timeout=600s keycloak --all -n "$CAMUNDA_NAMESPACE"
echo "  Keycloak instance ready."

echo ""
echo "All operators deployed successfully."
