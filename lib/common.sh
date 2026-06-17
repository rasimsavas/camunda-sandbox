#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-camunda-platform-local}"
CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
CAMUNDA_RELEASE_NAME="${CAMUNDA_RELEASE_NAME:-camunda}"
CAMUNDA_HELM_CHART_VERSION="${CAMUNDA_HELM_CHART_VERSION:-14.4.1}"
SECONDARY_STORAGE="${SECONDARY_STORAGE:-postgres}"
CAMUNDA_MODE="${CAMUNDA_MODE:-no-domain}"
CAMUNDA_VERSION="${CAMUNDA_VERSION:-$(cat "$PROJECT_DIR/.camunda-version" 2>/dev/null || echo "8.9")}"

export CLUSTER_NAME CAMUNDA_NAMESPACE CAMUNDA_RELEASE_NAME CAMUNDA_HELM_CHART_VERSION SECONDARY_STORAGE CAMUNDA_MODE CAMUNDA_VERSION

CONFIGS_DIR="$PROJECT_DIR/configs"
HELM_VALUES_DIR="$PROJECT_DIR/helm-values"
PROCESSES_DIR="$PROJECT_DIR/processes"
SCRIPTS_DIR="$PROJECT_DIR/scripts"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: Required command '$1' not found. Run scripts/01-install-tools.sh first."
        exit 1
    fi
}

wait_for_pods() {
    local namespace="${1:-$CAMUNDA_NAMESPACE}"
    local timeout="${2:-600}"
    echo "Waiting for all pods in $namespace to be Ready (timeout: ${timeout}s)..."
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local not_ready
        not_ready=$(kubectl get pods -n "$namespace" --field-selector=status.phase!=Running -o name 2>/dev/null | wc -l)
        local containers_not_ready
        containers_not_ready=$(kubectl get pods -n "$namespace" -o json 2>/dev/null | python3 -c "
import sys,json
try:
    items = json.load(sys.stdin).get('items',[])
    count = sum(1 for p in items for c in p.get('status',{}).get('containerStatuses',[]) if not c.get('ready',False))
    print(count)
except: print(0)
" 2>/dev/null || echo "1")
        if [ "$not_ready" -eq 0 ] && [ "$containers_not_ready" -eq 0 ]; then
            echo "All pods are Running and Ready."
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: Timeout waiting for pods. Current status:"
    kubectl get pods -n "$namespace" -o wide
    return 1
}

get_admin_password() {
    kubectl get secret camunda-credentials -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.identity-first-user-password}' 2>/dev/null | base64 -d
}

get_keycloak_credentials() {
    echo "Keycloak Admin Username: $(kubectl get secret keycloak-initial-admin -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)"
    echo "Keycloak Admin Password: $(kubectl get secret keycloak-initial-admin -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
}