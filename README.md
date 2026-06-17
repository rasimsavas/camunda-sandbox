# fast-setup — Camunda 8.9 on Kind

Deploy Camunda 8.9 Self-Managed on a local Kind cluster with a single command or step-by-step scripts.

## What Gets Deployed

- **Kind cluster** (3 nodes, K8s v1.34)
- **CloudNativePG** operator + 4 PostgreSQL clusters
- **Keycloak** operator + instance (no-domain mode, port 18080)
- **Camunda 8.9.7** (Helm chart 14.4.1) — Zeebe, Operate, Tasklist, Connectors, Identity, Web Modeler, Console
- **No Elasticsearch** — uses PostgreSQL for secondary storage (RDBMS mode)
- **No Optimize** — not supported in RDBMS mode

## Prerequisites

- Linux (tested on Ubuntu)
- Docker installed and running
- `curl`, `openssl`, `python3`
- `sudo` access (for `/etc/hosts` edit)
- [just](https://github.com/casey/just) (optional, for task runner)

## Quick Start

### Using just (recommended)

```bash
# Install just if you don't have it
cargo install just
# or: bash <(curl -fsSL https://just.systems/install.sh)

# 1. Install tools (kind, kubectl, helm, yq, jq)
just install

# Make sure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

# 2-6. Full deploy (cluster + operators + camunda + api + example)
just create-cluster
just deploy
```

### Using scripts directly

```bash
# 1. Install tools
./scripts/01-install-tools.sh

export PATH="$HOME/.local/bin:$PATH"

# 2. Create Kind cluster
./scripts/02-create-cluster.sh

# 3. Deploy operators (CNPG, Keycloak)
./scripts/03-deploy-operators.sh

# 4. Deploy Camunda via Helm
./scripts/04-deploy-camunda.sh

# 5. Setup CLI API access
./scripts/05-setup-api-access.sh

# 6. Deploy example process
./scripts/06-deploy-example-process.sh
```

## Port-Forward

Scripts 05 and 06 require port-forwarding. Run in a separate terminal:

```bash
just port-forward
# or: ./scripts/port-forward.sh
```

| Service | URL |
|---------|-----|
| Zeebe gRPC | `localhost:26500` |
| Zeebe REST / Operate | `localhost:8080` |
| Web Modeler | `localhost:8070` |
| Connectors | `localhost:8088` |
| Console | `localhost:8087` |
| Identity | `localhost:8085` |
| Keycloak | `localhost:18080/auth` |

## Credentials

```bash
just credentials
# or: ./scripts/get-credentials.sh
```

## Status

```bash
just status
# or: ./scripts/status.sh
```

## Cleanup

```bash
just cleanup
# or: ./scripts/cleanup.sh
```

## API Access (CLI)

```bash
ADMIN_PASS=$(just credentials-quiet)
TOKEN=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=api-cli" \
  -d "username=admin" -d "password=$ADMIN_PASS" | jq -r .access_token)

curl -s http://localhost:8080/v2/topology -H "Authorization: Bearer $TOKEN" | jq
```

## Example Process

The included `example-process.bpmn` is an order processing workflow:

1. **Start** → **Process Order** (service task, type `process-order`) → **Approved?**
2. `approved=true` → **Order Approved**
3. `approved=false` → **Order Rejected**

Step 06 starts two instances with different `approved` values so each path is exercised.

## Configuration

All settings are in `lib/common.sh` with environment variable overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `camunda-platform-local` | Kind cluster name |
| `CAMUNDA_NAMESPACE` | `camunda` | K8s namespace |
| `CAMUNDA_RELEASE_NAME` | `camunda` | Helm release name |
| `CAMUNDA_HELM_CHART_VERSION` | `14.4.1` | Helm chart version |
| `CAMUNDA_VERSION` | `8.9` (from `.camunda-version`) | Camunda major.minor version |
| `SECONDARY_STORAGE` | `postgres` | `postgres` (RDBMS) or `elasticsearch` |
| `CAMUNDA_MODE` | `no-domain` | Deployment mode |

## Directory Structure

```
fast-setup/
├── .camunda-version         ← Camunda version pin (8.9)
├── justfile                 ← Task runner recipes
├── lib/common.sh            ← Shared env vars + helper functions
├── configs/                 ← Kind, CNPG, Keycloak configs
│   ├── kind-cluster.yaml
│   ├── pg-clusters.yml
│   ├── pg-orchestration-cluster.yml
│   └── keycloak-instance.yml
├── helm-values/             ← Camunda Helm values files
│   ├── values-no-domain.yml
│   ├── camunda-keycloak-no-domain.yml
│   ├── camunda-identity-pg.yml
│   ├── camunda-webmodeler-pg.yml
│   └── camunda-rdbms.yml
├── processes/               ← BPMN process definitions
│   └── example-process.bpmn
└── scripts/                 ← Step-by-step deployment scripts
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

## Known Issues

- **OOMKilled**: Identity, Zeebe, and Connectors need increased memory limits (baked into `values-no-domain.yml`)
- **Keycloak client**: The `api-cli` public client requires `directAccessGrantsEnabled=true`
- **/etc/hosts**: Must contain `127.0.0.1 keycloak-service` for no-domain mode
- **Port-forward**: Required for localhost API access — no ingress controller in no-domain mode