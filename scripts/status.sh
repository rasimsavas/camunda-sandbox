#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl

echo "=== Cluster ==="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "  $CLUSTER_NAME: running"
else
    echo "  $CLUSTER_NAME: not running"
    exit 0
fi

echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide 2>/dev/null || echo "  Cannot connect to cluster"

echo ""
echo "=== Pods ($CAMUNDA_NAMESPACE) ==="
kubectl get pods -n "$CAMUNDA_NAMESPACE" -o wide 2>/dev/null || echo "  Namespace not found"

echo ""
echo "=== Services ($CAMUNDA_NAMESPACE) ==="
kubectl get svc -n "$CAMUNDA_NAMESPACE" 2>/dev/null || echo "  No services found"
