#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl

echo "=== Deleting Kind cluster: $CLUSTER_NAME ==="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    kind delete cluster --name "$CLUSTER_NAME"
    echo "  Cluster deleted."
else
    echo "  Cluster not found."
fi

echo ""
echo "=== Removing /etc/hosts entries ==="
if grep -q "keycloak-service" /etc/hosts 2>/dev/null; then
    sudo sed -i '/keycloak-service/d' /etc/hosts
    echo "  Host entries removed."
else
    echo "  No host entries found."
fi

echo ""
echo "Cleanup complete."
