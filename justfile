set positional-arguments

export PATH := env_var_or_default("HOME", env("HOME")) + "/.local/bin:" + env_var_or_default("PATH", env("PATH"))

# Default Camunda namespace
CAMUNDA_NAMESPACE := env_var_or_default("CAMUNDA_NAMESPACE", "camunda")

# List all available recipes
default:
    @just --list

# Install kind, kubectl, helm, yq, jq to ~/.local/bin
install:
    bash scripts/01-install-tools.sh

# Create Kind cluster + namespace + /etc/hosts entry
create-cluster:
    bash scripts/02-create-cluster.sh

# Deploy CNPG operator, PG clusters, Keycloak operator + instance
deploy-operators:
    bash scripts/03-deploy-operators.sh

# Deploy Camunda via Helm
deploy-camunda:
    bash scripts/04-deploy-camunda.sh

# Create api-cli Keycloak client + grant admin roles
setup-api:
    bash scripts/05-setup-api-access.sh

# Deploy example BPMN + start process instances
deploy-example:
    bash scripts/06-deploy-example-process.sh

# Full deploy: operators + camunda + api access + example process
deploy: deploy-operators deploy-camunda setup-api deploy-example

# Port-forward all Camunda services (blocks until Ctrl+C)
port-forward:
    bash scripts/port-forward.sh

# Print admin password and Keycloak credentials
credentials:
    bash scripts/get-credentials.sh

# Print admin password only (for scripting)
credentials-quiet:
    bash scripts/get-credentials.sh -q

# Show cluster, pods, services status
status:
    bash scripts/status.sh

# Show detected LAN IP address for browser access from other machines
lan-ip:
    @bash -c 'source lib/common.sh && echo "$CAMUNDA_LAN_IP"'

# Show Windows hosts file entry needed for LAN browser access
lan-hosts:
    @bash -c 'source lib/common.sh && echo "$CAMUNDA_LAN_IP  keycloak-service"'

# Delete Kind cluster + remove /etc/hosts entries
cleanup:
    bash scripts/cleanup.sh