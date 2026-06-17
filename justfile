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

# Build custom secret provider JAR with Maven (Docker-based)
build-custom-connectors-jar:
    bash -c '\
        M2_REPO="c8-extensions/.m2/repository" && \
        mkdir -p "$$M2_REPO" && \
        docker run --rm \
            -v "$(pwd)/c8-extensions/custom-secret-provider:/workspace" \
            -v "$(pwd)/$$M2_REPO:/root/.m2/repository" \
            -w /workspace \
            maven:3.9-eclipse-temurin-17 \
            mvn clean package'

# Build custom Docker image for connectors
build-custom-connectors-image:
    docker build -t camunda/connectors-bundle:8.9.5-custom-secrets c8-extensions/custom-secret-provider/

# Load custom connectors image into Kind cluster
load-custom-connectors-image:
    kind load docker-image camunda/connectors-bundle:8.9.5-custom-secrets --name camunda-platform-local

# Full rebuild and redeploy of custom connectors (JAR → image → kind → deploy)
rebuild-custom-connectors:
    bash c8-extensions/build-deploy-custom-connectors.sh

# Create the connector-secrets K8s Secret with test values
create-connector-secrets:
    kubectl apply -f configs/connector-secrets.yaml

# Deploy custom connectors with volume mounts and secrets
deploy-custom-connectors:
    bash scripts/deploy-custom-connectors.sh
