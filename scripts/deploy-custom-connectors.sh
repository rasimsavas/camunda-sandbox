#!/bin/bash
set -euo pipefail
# deploy-custom-connectors.sh
# Update the connectors deployment with the custom image, volume mount, and secrets.

NAMESPACE="${CAMUNDA_NAMESPACE:-camunda}"
DEPLOYMENT="${CONNECTORS_DEPLOYMENT:-camunda-connectors}"
IMAGE="${CONNECTORS_IMAGE:-camunda/connectors-bundle:8.9.5-custom-secrets}"

echo "Updating deployment $DEPLOYMENT in namespace $NAMESPACE..."

kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/../configs/connector-secrets.yaml" 2>/dev/null || true

kubectl set image "deployment/$DEPLOYMENT" -n "$NAMESPACE" \
    connectors="$IMAGE" 2>/dev/null || true

kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" --type=strategic \
    -p '{
        "spec": {
            "template": {
                "spec": {
                    "volumes": [
                        {
                            "name": "connector-secrets",
                            "secret": {
                                "secretName": "connector-secrets"
                            }
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
                                    "readOnly": true
                                }
                            ]
                        }
                    ]
                }
            }
        }
    }'

kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s

echo "Deployment complete."
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=connectors
