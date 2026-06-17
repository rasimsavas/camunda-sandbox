#!/bin/bash
set -euo pipefail

# build-deploy-custom-connectors.sh
# Build the custom secret provider JAR, Docker image, load into Kind, and redeploy connectors.
#
# Prerequisites:
#   - Docker
#   - kind
#   - kubectl
#   - Cluster: camunda-platform-local (configurable via CLUSTER_NAME env var)
#   - Namespace: camunda (configurable via CAMUNDA_NAMESPACE env var)
#
# Usage:
#   ./build-deploy-custom-connectors.sh
#
# Environment variables:
#   CLUSTER_NAME          Kind cluster name (default: camunda-platform-local)
#   CAMUNDA_NAMESPACE     Kubernetes namespace (default: camunda)
#   CONNECTORS_DEPLOYMENT Deployment name (default: camunda-connectors)
#   IMAGE_TAG             Custom image tag (default: 8.9.5-custom-secrets)

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$PROJECT_DIR/c8-extensions/custom-secret-provider"
M2_REPO="$PROJECT_DIR/c8-extensions/.m2/repository"

CLUSTER_NAME="${CLUSTER_NAME:-camunda-platform-local}"
CAMUNDA_NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
CONNECTORS_DEPLOYMENT="${CONNECTORS_DEPLOYMENT:-camunda-connectors}"
IMAGE_TAG="${IMAGE_TAG:-8.9.5-custom-secrets}"
BASE_IMAGE="${BASE_IMAGE:-camunda/connectors-bundle:8.9.5}"
IMAGE_NAME="camunda/connectors-bundle:${IMAGE_TAG}"

echo "============================================"
echo " Building Custom Connectors Image"
echo "============================================"
echo "  Project dir:    $EXT_DIR"
echo "  Base image:     $BASE_IMAGE"
echo "  Target image:   $IMAGE_NAME"
echo "  Cluster:        $CLUSTER_NAME"
echo "  Namespace:      $CAMUNDA_NAMESPACE"
echo "  Deployment:     $CONNECTORS_DEPLOYMENT"
echo "============================================"
echo ""

# Step 1: Build JAR with Maven (using Docker)
echo "[1/6] Building JAR with Maven (Docker)..."
mkdir -p "$M2_REPO"

docker run --rm \
    -v "$EXT_DIR:/workspace" \
    -v "$M2_REPO:/root/.m2/repository" \
    -w /workspace \
    maven:3.9-eclipse-temurin-17 \
    mvn clean package 2>&1 | tail -3

if [ ! -f "$EXT_DIR/target/custom-secret-provider-1.0.0.jar" ]; then
    echo "ERROR: JAR build failed!"
    exit 1
fi
echo "  JAR built: $(ls -lh "$EXT_DIR/target/custom-secret-provider-1.0.0.jar" | awk '{print $5}')"

# Step 2: Build Docker image
echo ""
echo "[2/6] Building Docker image..."
docker build \
    -t "$IMAGE_NAME" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    "$EXT_DIR" 2>&1 | tail -3

# Step 3: Load into Kind
echo ""
echo "[3/6] Loading image into Kind cluster '$CLUSTER_NAME'..."
kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME" 2>&1

# Step 4: Apply connector-secrets K8s Secret
echo ""
echo "[4/6] Applying connector-secrets K8s Secret..."
SECRET_FILE="$PROJECT_DIR/configs/connector-secrets.yaml"
if [ -f "$SECRET_FILE" ]; then
    kubectl apply -f "$SECRET_FILE" 2>&1
else
    echo "  WARNING: $SECRET_FILE not found — skipping secret creation"
fi

# Step 5: Update deployment (image + env vars from secrets)
echo ""
echo "[5/6] Updating K8s deployment..."
kubectl set image "deployment/$CONNECTORS_DEPLOYMENT" -n "$CAMUNDA_NAMESPACE" \
    connectors="$IMAGE_NAME" 2>&1

# Remove the old volume mount for connector-secrets (strategic merge with $patch: delete)
# and inject all secret values as environment variables using secretKeyRef
kubectl patch deployment "$CONNECTORS_DEPLOYMENT" -n "$CAMUNDA_NAMESPACE" --type='strategic' \
    -p '{
        "spec": {
            "template": {
                "spec": {
                    "volumes": [
                        {
                            "name": "connector-secrets",
                            "$patch": "delete"
                        }
                    ],
                    "containers": [
                        {
                            "name": "connectors",
                            "imagePullPolicy": "IfNotPresent",
                            "volumeMounts": [
                                {
                                    "name": "connector-secrets",
                                    "mountPath": "/etc/camunda/secrets",
                                    "$patch": "delete"
                                }
                            ],
                            "env": [
                                {
                                    "name": "SECRET_ORDER_BASE_AMOUNT",
                                    "valueFrom": {
                                        "secretKeyRef": {
                                            "name": "connector-secrets",
                                            "key": "ORDER_BASE_AMOUNT"
                                        }
                                    }
                                },
                                {
                                    "name": "SECRET_ORDER_DISCOUNT_RATE",
                                    "valueFrom": {
                                        "secretKeyRef": {
                                            "name": "connector-secrets",
                                            "key": "ORDER_DISCOUNT_RATE"
                                        }
                                    }
                                },
                                {
                                    "name": "SECRET_ORDER_API_KEY",
                                    "valueFrom": {
                                        "secretKeyRef": {
                                            "name": "connector-secrets",
                                            "key": "ORDER_API_KEY"
                                        }
                                    }
                                },
                                {
                                    "name": "SECRET_CUSTOMER_WELCOME_MSG",
                                    "valueFrom": {
                                        "secretKeyRef": {
                                            "name": "connector-secrets",
                                            "key": "CUSTOMER_WELCOME_MSG"
                                        }
                                    }
                                },
                                {
                                    "name": "CAMUNDA_CONNECTOR_SECRETPROVIDER_ENVIRONMENT_PREFIX",
                                    "value": "CONNECTOR_"
                                },
                                {
                                    "name": "SECRET_MY_TEST_KEY",
                                    "value": "hello-from-custom-secret-provider"
                                }
                            ]
                        }
                    ]
                }
            }
        }
    }' 2>&1

# Step 6: Wait for rollout
echo ""
echo "[6/6] Waiting for rollout..."
kubectl rollout status "deployment/$CONNECTORS_DEPLOYMENT" -n "$CAMUNDA_NAMESPACE" --timeout=120s 2>&1

echo ""
echo "============================================"
echo " Custom Connectors deployment complete!"
echo "============================================"
echo ""
echo "  Pod status:"
kubectl get pods -n "$CAMUNDA_NAMESPACE" -l app.kubernetes.io/component=connectors
echo ""
echo "  Check logs: kubectl logs -n $CAMUNDA_NAMESPACE deploy/$CONNECTORS_DEPLOYMENT"
echo ""
echo "  Verify env vars:"
echo "    kubectl exec -n $CAMUNDA_NAMESPACE deploy/$CONNECTORS_DEPLOYMENT -- env | grep SECRET_"
