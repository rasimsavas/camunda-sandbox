#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

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
    if sudo sed -i '/keycloak-service/d' /etc/hosts 2>/dev/null; then
        echo "  Host entries removed."
    else
        echo "  WARNING: Cannot edit /etc/hosts (sudo unavailable or no TTY)."
        echo "  Remove manually with:"
        echo "    sudo sed -i '/keycloak-service/d' /etc/hosts"
    fi
else
    echo "  No host entries found."
fi

echo ""
echo "Cleanup complete."