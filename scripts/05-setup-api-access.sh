#!/bin/bash
set -euo pipefail

# 05-setup-api-access.sh — Create api-cli Keycloak client + grant admin roles for CLI REST API access
# Prerequisites: 04-deploy-camunda.sh completed, jq in PATH

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl
require_cmd jq
require_port_forward

KEYCLOAK_PASS=$(kubectl get secret keycloak-initial-admin -n "$CAMUNDA_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
KC_ADMIN_TOKEN=$(curl -sf http://localhost:18080/auth/realms/master/protocol/openid-connect/token \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=temp-admin" \
    -d "password=$KEYCLOAK_PASS" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# --- Create api-cli public client ---
echo "=== Creating api-cli Keycloak client for CLI access ==="

EXISTING_API_CLI=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/clients?clientId=api-cli" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "
import sys,json
clients = json.load(sys.stdin)
for c in clients: print(c['id'])
" 2>&1 || echo "")

if [ -n "$EXISTING_API_CLI" ]; then
    echo "  api-cli client already exists."
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:18080/auth/admin/realms/camunda-platform/clients" \
        -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "api-cli",
            "name": "API CLI",
            "enabled": true,
            "publicClient": true,
            "directAccessGrantsEnabled": true,
            "standardFlowEnabled": false,
            "serviceAccountsEnabled": false,
            "redirectUris": [],
            "webOrigins": []
        }')
    echo "  api-cli created (status: $HTTP_CODE)"
fi

# --- Grant orchestration-api roles to admin user ---
echo ""
echo "=== Granting API roles to admin user ==="

ADMIN_USER_ID=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/users?username=admin" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

ORCH_API_ID=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/clients" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c['clientId'] == 'orchestration-api': print(c['id'])
")

ORCH_API_ROLES=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/clients/$ORCH_API_ID/roles" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "
import sys,json
roles = json.load(sys.stdin)
print(json.dumps([{'id': r['id'], 'name': r['name']} for r in roles]))
")

curl -sf -X POST "http://localhost:18080/auth/admin/realms/camunda-platform/users/$ADMIN_USER_ID/role-mappings/clients/$ORCH_API_ID" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ORCH_API_ROLES" 2>/dev/null || echo "  Roles may already be assigned."

# Grant realm-admin
REALM_MGMT_ID=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/clients" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c['clientId'] == 'realm-management': print(c['id'])
")

REALM_ADMIN_ID=$(curl -sf "http://localhost:18080/auth/admin/realms/camunda-platform/clients/$REALM_MGMT_ID/roles/realm-admin" \
    -H "Authorization: Bearer $KC_ADMIN_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

if [ -n "$REALM_ADMIN_ID" ]; then
    curl -sf -X POST "http://localhost:18080/auth/admin/realms/camunda-platform/users/$ADMIN_USER_ID/role-mappings/clients/$REALM_MGMT_ID" \
        -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"id\":\"$REALM_ADMIN_ID\",\"name\":\"realm-admin\"}]" 2>/dev/null || echo "  realm-admin may already be assigned."
fi

echo "  API roles granted to admin user."

# --- Verify ---
echo ""
echo "=== Verifying API access ==="
ADMIN_PASS=$(get_admin_password)
RESULT=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
    -d "grant_type=password" \
    -d "client_id=api-cli" \
    -d "username=admin" \
    -d "password=$ADMIN_PASS")

echo "$RESULT" | python3 -c "
import sys,json
d = json.load(sys.stdin)
if 'access_token' in d:
    print('  SUCCESS: Token obtained (length: ' + str(len(d['access_token'])) + ')')
else:
    print('  ERROR: ' + d.get('error','') + ' — ' + d.get('error_description','')[:80])
"

echo ""
echo "=== Ubuntu Server (API Access) ==="
echo "Use these commands to get a token:"
echo "  ADMIN_PASS=\$(scripts/get-credentials.sh -q)"
echo "  TOKEN=\$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \\"
echo "    -d 'grant_type=password' -d 'client_id=api-cli' \\"
echo "    -d 'username=admin' -d \"password=\$ADMIN_PASS\" | jq -r .access_token)"

if [ -n "$CAMUNDA_LAN_IP" ] && [ "$CAMUNDA_LAN_IP" != "127.0.0.1" ]; then
    echo ""
    echo "=== Windows 11 (Browser Access) ==="
    echo ""
    echo "Step 1: Add this line to C:\\Windows\\System32\\drivers\\etc\\hosts (run Notepad as Admin):"
    echo "  ${CAMUNDA_LAN_IP}  keycloak-service"
    echo ""
    echo "Step 2: Open these URLs in a Windows browser:"
    echo "  - Operate / Tasklist: http://keycloak-service:8080"
    echo "  - Web Modeler:        http://keycloak-service:8070"
    echo "  - Console:             http://keycloak-service:8087"
    echo "  - Identity:             http://keycloak-service:8085"
    echo "  - Keycloak:             http://keycloak-service:18080/auth"
fi
