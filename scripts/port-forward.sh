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

kubectl port-forward --address 0.0.0.0 svc/camunda-zeebe-gateway 26500:26500 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-zeebe-gateway 8080:8080 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-web-modeler-restapi 8070:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-web-modeler-websockets 8086:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-connectors 8088:8080 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-console 8087:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/camunda-identity 8085:80 -n "$CAMUNDA_NS" &>/dev/null &
kubectl port-forward --address 0.0.0.0 svc/keycloak-service 18080:18080 -n "$CAMUNDA_NS" &>/dev/null &

echo "  Waiting for services to become reachable..."
READY=false
for i in $(seq 1 30); do
    if curl -sf -o /dev/null http://localhost:18080/auth/ 2>/dev/null; then
        READY=true
        break
    fi
    sleep 2
done

ADMIN_PASS=$(kubectl get secret camunda-credentials -n "$CAMUNDA_NS" -o jsonpath='{.data.identity-first-user-password}' 2>/dev/null | base64 -d || echo "N/A")

if [ "$READY" = true ]; then
    echo ""
    echo "=== Ubuntu Server (localhost) ==="
    echo "Services available at:"
    echo "  - Zeebe gRPC API:    localhost:26500"
    echo "  - Zeebe REST API:    localhost:8080   (Operate, Tasklist, Admin)"
    echo "  - Web Modeler:       localhost:8070"
    echo "  - WebSockets:        localhost:8086   (Modeler live sync)"
    echo "  - Connectors:        localhost:8088"
    echo "  - Console:           localhost:8087"
    echo "  - Identity:          localhost:8085"
    echo "  - Keycloak:          localhost:18080/auth"
    echo ""
    echo "Login: admin / $ADMIN_PASS"

    if [ -n "$CAMUNDA_LAN_IP" ] && [ "$CAMUNDA_LAN_IP" != "127.0.0.1" ]; then
        echo ""
        echo "=== Windows 11 (LAN Access) ==="
        echo ""
        echo "Step 1: Add this line to C:\\Windows\\System32\\drivers\\etc\\hosts (run Notepad as Admin):"
        echo "  ${CAMUNDA_LAN_IP}  keycloak-service"
        echo ""
        echo "Step 2: Open these URLs in a Windows browser:"
        echo "  - Operate / Tasklist: http://keycloak-service:8080"
        echo "  - Web Modeler:        http://keycloak-service:8070"
        echo "  - Console:             http://keycloak-service:8087"
        echo "  - Identity:             http://keycloak-service:8085/managementidentity/"
        echo "  - Keycloak:             http://keycloak-service:18080/auth"
        echo ""
        echo "Step 3: Login with username: admin  password: $ADMIN_PASS"
    fi
else
    echo ""
    echo "WARNING: Keycloak did not become reachable within 60 seconds."
    echo "  The services may still be starting up. Check with: just status"
    echo ""
    echo "Login (when ready): admin / $ADMIN_PASS"
fi

echo ""
wait