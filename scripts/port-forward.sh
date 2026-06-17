#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl

CAMUNDA_NS="${CAMUNDA_NAMESPACE:-camunda}"

cleanup() {
    echo ""
    echo "Stopping all port-forwards..."
    jobs -p | xargs -r kill 2>/dev/null || true
    pkill -P $$ 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM

echo "Starting port-forwards (Ctrl+C to stop)..."

kubectl port-forward svc/camunda-zeebe-gateway 26500:26500 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/camunda-zeebe-gateway 8080:8080 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/camunda-web-modeler-restapi 8070:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/camunda-connectors 8088:8080 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/camunda-console 8087:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/camunda-identity 8085:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward svc/keycloak-service 18080:18080 -n "$CAMUNDA_NS" &>/dev/null &

echo "  Waiting for services to become reachable..."
READY=false
for i in $(seq 1 30); do
    if curl -sf -o /dev/null http://localhost:18080/auth/ 2>/dev/null; then
        READY=true
        break
    fi
    sleep 2
done

if [ "$READY" = true ]; then
    echo ""
    echo "Services available at:"
    echo "  - Zeebe gRPC API:    localhost:26500"
    echo "  - Zeebe REST API:    localhost:8080   (Operate, Tasklist, Admin)"
    echo "  - Web Modeler:       localhost:8070"
    echo "  - Connectors:        localhost:8088"
    echo "  - Console:           localhost:8087"
    echo "  - Identity:          localhost:8085"
    echo "  - Keycloak:          localhost:18080/auth"
    echo ""
    ADMIN_PASS=$(kubectl get secret camunda-credentials -n "$CAMUNDA_NS" -o jsonpath='{.data.identity-first-user-password}' 2>/dev/null | base64 -d || echo "N/A")
    echo "Login: admin / $ADMIN_PASS"
else
    echo ""
    echo "WARNING: Keycloak did not become reachable within 60 seconds."
    echo "  The services may still be starting up. Check with: just status"
fi

echo ""
wait