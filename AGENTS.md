# camunda-sandbox/AGENTS.md

## Overview

Standalone project for deploying **Camunda 8.9** on a local **Kind** cluster.
Everything lives in this repository — no relative imports from external directories.

## Architecture

- **Camunda 8.9.7** (Helm chart `14.4.1`) in no-domain mode
- **PostgreSQL** via CloudNativePG operator (identity, keycloak, webmodeler, orchestration)
- **Keycloak** via the Keycloak operator (separate instance for OIDC)
- **No Elasticsearch** — RDBMS secondary storage (`SECONDARY_STORAGE=postgres`)
- **No Optimize** — disabled by `camunda-rdbms.yml` overlay (not supported in RDBMS mode)

## Quick Start (using just)

```bash
just install          # Install kind, kubectl, helm, yq, jq
just create-cluster    # Create Kind cluster + namespace + hosts
just deploy            # Full deploy (operators → camunda → api → example process)
```

Or step-by-step with numbered scripts (see README).

**Important:** Steps 05 and 06 require port-forwarding. Start it before running them:
```bash
just port-forward
```

## Verify Deployment

After `just deploy`, verify everything is working:

```bash
just status              # All pods should be 1/1 Running
just credentials         # Print admin password
just port-forward        # Start port-forward (separate terminal)

# Quick API health check:
ADMIN_PASS=$(just credentials-quiet)
TOKEN=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=api-cli" \
  -d "username=admin" -d "password=$ADMIN_PASS" | jq -r .access_token)
curl -s http://localhost:8080/v2/topology -H "Authorization: Bearer $TOKEN" | jq
```

## Scripts

| # | Script | Purpose |
|---|--------|---------|
| 01 | `01-install-tools.sh` | Install kind, kubectl, helm, yq, jq to `~/.local/bin` |
| 02 | `02-create-cluster.sh` | Create Kind cluster + namespace + `/etc/hosts` entry |
| 03 | `03-deploy-operators.sh` | Deploy CNPG operator, PG clusters, Keycloak operator + instance |
| 04 | `04-deploy-camunda.sh` | Deploy Camunda via Helm (all values files) |
| 05 | `05-setup-api-access.sh` | Create `api-cli` Keycloak client, grant admin roles (requires port-forward) |
| 06 | `06-deploy-example-process.sh` | Deploy example BPMN + start process instances (requires port-forward) |

**Utility scripts:**
- `cleanup.sh` — Delete Kind cluster, remove `/etc/hosts` entries
- `get-credentials.sh` — Print admin password and Keycloak creds (`-q` for password only)
- `status.sh` — Show cluster, pods, services status
- `port-forward.sh` — Port-forward all Camunda services to localhost (waits for readiness)

## justfile Recipes

Run `just` or `just --list` to see all recipes:

```
just install           # Install kind, kubectl, helm, yq, jq
just create-cluster    # Create Kind cluster
just deploy-operators  # Deploy CNPG, PG clusters, Keycloak
just deploy-camunda    # Deploy Camunda via Helm
just setup-api         # Create api-cli client + grant roles
just deploy-example    # Deploy BPMN + start instances
just deploy            # Full deploy (all of the above)
just port-forward      # Port-forward services (blocks, waits for readiness)
just credentials       # Print admin credentials
just credentials-quiet # Print password only
just status            # Cluster/pod/service status
just cleanup           # Delete cluster + hosts entries
```

## Port-Forward Endpoints

After running `just port-forward`:

| Service | URL | Description |
|---------|-----|-------------|
| Zeebe gRPC | `localhost:26500` | gRPC gateway |
| Zeebe REST / Operate | `localhost:8080` | REST API, Operate UI, Tasklist |
| Web Modeler | `localhost:8070` | BPMN modeler |
| Connectors | `localhost:8088` | Connector runtime |
| Console | `localhost:8087` | Management console |
| Identity | `localhost:8085` | Identity management |
| Keycloak | `localhost:18080/auth` | OIDC provider |

## API Access (CLI)

```bash
ADMIN_PASS=$(just credentials-quiet)
TOKEN=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=api-cli" \
  -d "username=admin" -d "password=$ADMIN_PASS" | jq -r .access_token)

curl -s http://localhost:8080/v2/topology -H "Authorization: Bearer $TOKEN" | jq
```

## Key Files

```
camunda-sandbox/
├── .camunda-version         ← Camunda version pin (8.9)
├── justfile                 ← Task runner recipes
├── lib/common.sh            ← shared env vars + helper functions (including require_port_forward)
├── configs/
│   ├── kind-cluster.yaml            ← Kind cluster config (3 nodes, v1.34.0)
│   ├── pg-clusters.yml              ← PG clusters for identity, keycloak, webmodeler
│   ├── pg-orchestration-cluster.yml ← PG cluster for orchestration (RDBMS mode)
│   └── keycloak-instance.yml        ← Keycloak CR (no-domain, port 18080)
├── helm-values/
│   ├── values-no-domain.yml           ← Base values (no ingress, resource limits)
│   ├── camunda-keycloak-no-domain.yml ← External Keycloak config
│   ├── camunda-identity-pg.yml        ← Identity → external PostgreSQL
│   ├── camunda-webmodeler-pg.yml      ← Web Modeler → external PostgreSQL
│   └── camunda-rdbms.yml             ← RDBMS secondary storage + disable Optimize
├── processes/
│   └── example-process.bpmn        ← Example order processing BPMN
└── scripts/
    ├── 01-install-tools.sh         ← Install kind, kubectl, helm, yq, jq
    ├── 02-create-cluster.sh        ← Create Kind cluster + namespace + /etc/hosts
    ├── 03-deploy-operators.sh      ← Deploy CNPG, PG clusters, Keycloak
    ├── 04-deploy-camunda.sh        ← Deploy Camunda via Helm
    ├── 05-setup-api-access.sh      ← Create api-cli client + grant roles (requires port-forward)
    ├── 06-deploy-example-process.sh ← Deploy BPMN + start instances (requires port-forward)
    ├── cleanup.sh                  ← Delete cluster + remove /etc/hosts
    ├── get-credentials.sh          ← Print credentials (-q for password only)
    ├── port-forward.sh             ← Port-forward all services (waits for readiness)
    └── status.sh                   ← Show cluster/pod/service status
```

## Environment Variables

All overridable via environment (see `lib/common.sh` defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `camunda-platform-local` | Kind cluster name |
| `CAMUNDA_NAMESPACE` | `camunda` | K8s namespace |
| `CAMUNDA_RELEASE_NAME` | `camunda` | Helm release name |
| `CAMUNDA_HELM_CHART_VERSION` | `14.4.1` | Helm chart version |
| `CAMUNDA_VERSION` | `8.9` (from `.camunda-version`) | Camunda major.minor version |
| `SECONDARY_STORAGE` | `postgres` | `postgres` (RDBMS) or `elasticsearch` |
| `CAMUNDA_MODE` | `no-domain` | Deployment mode |

## Known Issues / Workarounds

- **OOMKilled**: Identity, Zeebe, and Connectors need increased memory limits (baked into `values-no-domain.yml`)
- **Keycloak client**: The `api-cli` public client requires `directAccessGrantsEnabled=true` (not `directGrantsEnabled`)
- **/etc/hosts**: Must contain `127.0.0.1 keycloak-service` for no-domain mode; script 02 adds it automatically
- **Docker group**: If `newgrp docker` is needed, wrap all kubectl/kind/helm commands accordingly
- **Port-forward**: Required for localhost API access — scripts 05 and 06 validate connectivity before proceeding
- **Cleanup sudo**: If running without a TTY, `cleanup.sh` cannot edit `/etc/hosts` automatically — remove the entry manually
- **Optimize**: Shown as `enabled: true` in `values-no-domain.yml` but overridden to `false` by `camunda-rdbms.yml` since Optimize doesn't support RDBMS mode

## Troubleshooting

### Pods stuck in CrashLoopBackOff / OOMKilled
```bash
kubectl describe pod <pod-name> -n camunda
kubectl get pod <pod-name> -n camunda -o jsonpath='{.spec.containers[*].resources}'
```

### Scripts 05/06 fail with connection refused
Ensure port-forward is running:
```bash
just port-forward
# Verify: curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/auth/
# Should return 302
```

### Token request returns invalid_grant
Re-run `just setup-api` — it's idempotent and will recreate the `api-cli` client if needed.