#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

require_cmd kubectl

if [ "${1:-}" = "-q" ]; then
    get_admin_password
    exit 0
fi

echo "=== Camunda Admin Credentials ==="
echo "  Username: admin"
echo "  Password: $(get_admin_password)"

echo ""
echo "=== Keycloak Admin Credentials ==="
get_keycloak_credentials

echo ""
echo "=== Port-forward command ==="
echo "  scripts/port-forward.sh"
