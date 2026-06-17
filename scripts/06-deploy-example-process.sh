#!/bin/bash
set -euo pipefail

# 06-deploy-example-process.sh — Deploy example BPMN process + start instances with variables
# Prerequisites: 05-setup-api-access.sh completed, port-forward running (or use in-cluster)

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl
require_cmd jq
require_port_forward

API_BASE="http://localhost:8080"
KC_BASE="http://localhost:18080"

get_token() {
    local admin_pass
    admin_pass=$(get_admin_password)
    curl -sf "$KC_BASE/auth/realms/camunda-platform/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=api-cli" \
        -d "username=admin" \
        -d "password=$admin_pass" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
}

ACCESS_TOKEN=$(get_token)

# --- Deploy BPMN ---
echo "=== Deploying example BPMN process ==="

DEPLOY_RESP=$(curl -sf "$API_BASE/v2/deployments" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -F "resources=@$PROCESSES_DIR/example-process.bpmn;type=application/xml;filename=example-process.bpmn")

PROCESS_KEY=$(echo "$DEPLOY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['deployments'][0]['processDefinition']['processDefinitionKey'])")
PROCESS_ID=$(echo "$DEPLOY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['deployments'][0]['processDefinition']['processDefinitionId'])")
PROCESS_VERSION=$(echo "$DEPLOY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['deployments'][0]['processDefinition']['processDefinitionVersion'])")

echo "  Process deployed: $PROCESS_ID (version: $PROCESS_VERSION, key: $PROCESS_KEY)"

# --- Start instances ---
echo ""
echo "=== Starting process instance 1 (approved=true) ==="

INSTANCE1_RESP=$(curl -sf -X POST "$API_BASE/v2/process-instances" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "processDefinitionId": "example-process",
        "variables": {
            "orderId": "ORD-2026-042",
            "amount": 1500,
            "customerName": "Acme Corp",
            "approved": true,
            "itemCount": 3
        }
    }')

INSTANCE1_KEY=$(echo "$INSTANCE1_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['processInstanceKey'])")
echo "  Instance started: key=$INSTANCE1_KEY, variables: orderId=ORD-2026-042, amount=1500, approved=true"

echo ""
echo "=== Starting process instance 2 (approved=false) ==="

INSTANCE2_RESP=$(curl -sf -X POST "$API_BASE/v2/process-instances" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "processDefinitionId": "example-process",
        "variables": {
            "orderId": "ORD-2026-043",
            "amount": 50000,
            "customerName": "Globex Inc",
            "approved": false,
            "itemCount": 1
        }
    }')

INSTANCE2_KEY=$(echo "$INSTANCE2_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['processInstanceKey'])")
echo "  Instance started: key=$INSTANCE2_KEY, variables: orderId=ORD-2026-043, amount=50000, approved=false"

echo ""
echo "=== Process instances running ==="
echo "  Instance 1 ($INSTANCE1_KEY): waiting at 'Process Order' task → will reach 'Order Approved'"
echo "  Instance 2 ($INSTANCE2_KEY): waiting at 'Process Order' task → will reach 'Order Rejected'"
echo ""
echo "Both instances are ACTIVE, waiting for a job worker for task type 'process-order'."
