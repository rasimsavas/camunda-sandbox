# fast-setup/AGENTS.md

## Overview

Standalone project for deploying **Camunda 8.9** on a local **Kind** cluster.
Everything lives in this repository — no relative imports from external directories.

## Architecture

- **Camunda 8.9.7** (Helm chart `14.4.1`) in no-domain mode
- **PostgreSQL** via CloudNativePG operator (identity, keycloak, webmodeler, orchestration)
- **Keycloak** via the Keycloak operator (separate instance for OIDC)
- **No Elasticsearch** — RDBMS secondary storage (`SECONDARY_STORAGE=postgres`)
- **No Optimize** — not supported in RDBMS mode

## Quick Start (using just)

```bash
just install          # Install kind, kubectl, helm, yq, jq
just create-cluster    # Create Kind cluster + namespace + hosts
just deploy            # Full deploy (operators → camunda → api → example process)
```

Or step-by-step with numbered scripts (see README).

## Scripts

| # | Script | Purpose |
|---|--------|---------|
| 01 | `01-install-tools.sh` | Install kind, kubectl, helm, yq, jq to `~/.local/bin` |
| 02 | `02-create-cluster.sh` | Create Kind cluster + namespace + `/etc/hosts` entry |
| 03 | `03-deploy-operators.sh` | Deploy CNPG operator, PG clusters, Keycloak operator + instance |
| 04 | `04-deploy-camunda.sh` | Deploy Camunda via Helm (all values files) |
| 05 | `05-setup-api-access.sh` | Create `api-cli` Keycloak client, grant admin roles |
| 06 | `06-deploy-example-process.sh` | Deploy example BPMN + start process instances |

**Utility scripts:**
- `cleanup.sh` — Delete Kind cluster, remove `/etc/hosts` entries
- `get-credentials.sh` — Print admin password and Keycloak creds (`-q` for password only)
- `status.sh` — Show cluster, pods, services status
- `port-forward.sh` — Port-forward all Camunda services to localhost

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
just port-forward      # Port-forward services (blocks)
just credentials       # Print admin credentials
just credentials-quiet # Print password only
just status            # Cluster/pod/service status
just cleanup           # Delete cluster + hosts entries
```

## Port-Forward Endpoints

After running `just port-forward`:

| Service | URL |
|---------|-----|
| Zeebe gRPC | `localhost:26500` |
| Zeebe REST / Operate | `localhost:8080` |
| Web Modeler | `localhost:8070` |
| Connectors | `localhost:8088` |
| Console | `localhost:8087` |
| Identity | `localhost:8085` |
| Keycloak | `localhost:18080/auth` |

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
fast-setup/
├── .camunda-version         ← Camunda version pin (8.9)
├── justfile                 ← Task runner recipes
├── lib/common.sh            ← shared env vars + helper functions
├── configs/
│   ├── kind-cluster.yaml
│   ├── pg-clusters.yml
│   ├── pg-orchestration-cluster.yml
│   └── keycloak-instance.yml
├── helm-values/
│   ├── values-no-domain.yml
│   ├── camunda-keycloak-no-domain.yml
│   ├── camunda-identity-pg.yml
│   ├── camunda-webmodeler-pg.yml
│   └── camunda-rdbms.yml
├── processes/
│   └── example-process.bpmn
└── scripts/
    ├── 01-install-tools.sh
    ├── 02-create-cluster.sh
    ├── 03-deploy-operators.sh
    ├── 04-deploy-camunda.sh
    ├── 05-setup-api-access.sh
    ├── 06-deploy-example-process.sh
    ├── cleanup.sh
    ├── get-credentials.sh
    ├── port-forward.sh
    └── status.sh
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
- **/etc/hosts**: Must contain `127.0.0.1 keycloak-service` for no-domain mode
- **Docker group**: If `newgrp docker` is needed, wrap all kubectl/kind/helm commands accordingly
- **Port-forward**: Required for localhost API access — no ingress controller in no-domain mode