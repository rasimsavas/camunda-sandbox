# camunda-sandbox — Camunda 8.9 on Kind

Deploy Camunda 8.9 Self-Managed on a local Kind cluster with a single command or step-by-step scripts.

## What Gets Deployed

| Component | Version | Notes |
|-----------|---------|-------|
| Kind cluster | v1.34.0 | 3-node (1 control-plane + 2 workers) |
| CloudNativePG | v1.28.1 | PostgreSQL operator |
| PostgreSQL | 17.9 | 4 clusters: identity, keycloak, webmodeler, orchestration |
| Keycloak | 26.5.7 | Separate operator-managed instance (port 18080) |
| Camunda Platform | 8.9.7 | Helm chart 14.4.1, no-domain mode |
| Zeebe / Operate / Tasklist | 8.9.7 | Orchestration engine + REST API on port 8080 |
| Identity | 8.9.4 | OIDC auth via Keycloak |
| Connectors | 8.9.5 | |
| Web Modeler | 8.9.4 | REST API + WebSockets |
| Console | 8.9.45 | |

No Elasticsearch — uses PostgreSQL for secondary storage (RDBMS mode).
No Optimize — not supported in RDBMS mode (disabled by `camunda-rdbms.yml` overlay).

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

# 2. Create Kind cluster + namespace + /etc/hosts entry
just create-cluster

# 3. Full deploy (operators → camunda → api → example process)
just deploy
```

> **Important:** Steps 5 and 6 (`setup-api`, `deploy-example`) require port-forwarding to be running. Start it in a separate terminal before running them:
> ```bash
> just port-forward
> ```

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

# --- Start port-forwarding in a separate terminal ---
./scripts/port-forward.sh

# 5. Setup CLI API access (requires port-forward)
./scripts/05-setup-api-access.sh

# 6. Deploy example process (requires port-forward)
./scripts/06-deploy-example-process.sh
```

## Verify Deployment

After deploying, check that everything is running:

```bash
just status
```

All pods should show `1/1` or `Running`:

```
NAME                          READY   STATUS    RESTARTS   AGE
camunda-zeebe-0               1/1     Running   0          5m
camunda-identity-xxx          1/1     Running   0          5m
camunda-console-xxx           1/1     Running   0          5m
camunda-connectors-xxx        1/1     Running   0          5m
camunda-web-modeler-restapi   1/1     Running   0          5m
...
```

Get credentials:

```bash
just credentials
# Username: admin
# Password: <random hex>
```

Quick health check via API (requires port-forward):

```bash
ADMIN_PASS=$(just credentials-quiet)
TOKEN=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=api-cli" \
  -d "username=admin" -d "password=$ADMIN_PASS" | jq -r .access_token)

# Zeebe topology
curl -s http://localhost:8080/v2/topology -H "Authorization: Bearer $TOKEN" | jq

# Active process instances
curl -s -X POST http://localhost:8080/v2/process-instances/search \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}' | jq
```

## Port-Forward

Scripts 05 and 06 require port-forwarding. Start in a separate terminal:

```bash
just port-forward
# or: ./scripts/port-forward.sh
```

| Service | URL | Description |
|---------|-----|-------------|
| Zeebe gRPC | `localhost:26500` | gRPC gateway |
| Zeebe REST / Operate | `localhost:8080` | REST API, Operate UI, Tasklist |
| Web Modeler | `localhost:8070` | BPMN modeler |
| WebSockets | `localhost:8086` | Modeler live sync |
| Connectors | `localhost:8088` | Connector runtime |
| Console | `localhost:8087` | Management console |
| Identity | `localhost:8085/managementidentity/` | Identity management |
| Keycloak | `localhost:18080/auth` | OIDC provider |

## API Access (CLI)

After running `just setup-api`, you can obtain tokens and call the REST API:

```bash
ADMIN_PASS=$(just credentials-quiet)
TOKEN=$(curl -s http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=api-cli" \
  -d "username=admin" -d "password=$ADMIN_PASS" | jq -r .access_token)

# List topology
curl -s http://localhost:8080/v2/topology -H "Authorization: Bearer $TOKEN" | jq

# Start a process instance
curl -s -X POST http://localhost:8080/v2/process-instances \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "processDefinitionId": "example-process",
    "variables": {
      "orderId": "ORD-2026-999",
      "amount": 5000,
      "customerName": "Test Customer",
      "approved": true,
      "itemCount": 2
    }
  }' | jq

# Search process instances
curl -s -X POST http://localhost:8080/v2/process-instances/search \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' | jq
```

## Example Process

The included `example-process.bpmn` is an order processing workflow:

1. **Start** → **Process Order** (service task, type `process-order`) → **Approved?**
2. `approved=true` → **Order Approved**
3. `approved=false` → **Order Rejected**

Script 06 deploys this process and starts two instances with different `approved` values so each path is exercised.

All instances stay in `ACTIVE` state at the `Process Order` service task until a job worker activates and completes jobs for task type `process-order`.

## Credentials

There are **two separate credential sets**:

| Service | Username | Password | Where to use |
|---------|----------|----------|---------------|
| Camunda apps (Operate, Tasklist, Console, Modeler, Identity) | `admin` | Run `just credentials-quiet` | All Camunda web apps |
| Keycloak Admin Console | `temp-admin` | Run `just credentials` | `keycloak-service:18080/auth/admin/` only |

```bash
just credentials         # Print both credential sets
just credentials-quiet   # Print Camunda admin password only (for scripting)
```

## LAN Access (Windows / Other Machines)

Port-forward binds to `0.0.0.0` (all interfaces), making services accessible from other machines on the same LAN.

### Ubuntu Server Steps

1. **Deploy Camunda with LAN overlay** (included automatically when `CAMUNDA_LAN_IP` is detected):
   ```bash
   just deploy-camunda
   just setup-api
   ```
   The LAN overlay (`helm-values/camunda-lan.yml`) changes browser-facing URLs from `localhost` to `keycloak-service`.

2. **Start port-forward** (in a separate terminal):
   ```bash
   just port-forward
   ```

3. **Note your LAN IP** (auto-detected):
   ```bash
   just lan-ip       # e.g. 192.168.1.14
   just lan-hosts    # prints: 192.168.1.14  keycloak-service
   ```

### Windows 11 Steps

1. **Edit the Windows hosts file** as Administrator.

   Open `C:\Windows\System32\drivers\etc\hosts` in Notepad (Run as Administrator) and add this line:

   ```
   <LAN_IP>  keycloak-service
   ```

   Replace `<LAN_IP>` with the output of `just lan-hosts` from the Ubuntu server. For example:
   ```
   192.168.1.14  keycloak-service
   ```

2. **Open a browser on Windows** and navigate to:

   | Service | URL |
   |---------|-----|
   | Operate / Tasklist | `http://keycloak-service:8080` |
   | Web Modeler | `http://keycloak-service:8070` |
   | Console | `http://keycloak-service:8087` |
   | Identity | `http://keycloak-service:8085/managementidentity/` |
   | Keycloak | `http://keycloak-service:18080/auth` |

3. **Login** with username `admin` and the password from `just credentials-quiet`.

### How It Works

1. **Ubuntu server** `/etc/hosts` has two entries: `127.0.0.1 keycloak-service` (for port-forward) and `<LAN_IP> keycloak-service`
2. **Windows hosts file** maps `keycloak-service` → Ubuntu server's LAN IP, so the browser can reach the port-forwarded services
3. **Helm overlay** (`camunda-lan.yml`) changes all browser-facing redirect URLs from `localhost` to `keycloak-service`, so OIDC login redirects work correctly from Windows
4. **Keycloak** is configured with `hostname.strict: false`, so it accepts requests from any hostname
5. **Port-forward** binds to `0.0.0.0`, so it accepts connections from any network interface (not just localhost)

Override auto-detected LAN IP with: `CAMUNDA_LAN_IP=192.168.1.100 just deploy-camunda`

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
| `CAMUNDA_LAN_IP` | auto-detected | LAN IP for browser access from other machines |

## Directory Structure

```
camunda-sandbox/
├── .camunda-version         ← Camunda version pin (8.9)
├── justfile                 ← Task runner recipes
├── lib/common.sh            ← Shared env vars + helper functions
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
│   ├── camunda-rdbms.yml             ← RDBMS secondary storage + disable Optimize
│   └── camunda-lan.yml               ← LAN overlay (redirect URLs use keycloak-service)
├── processes/
│   └── example-process.bpmn        ← Example order processing BPMN
└── scripts/
    ├── 01-install-tools.sh         ← Install kind, kubectl, helm, yq, jq
    ├── 02-create-cluster.sh        ← Create Kind cluster + namespace + /etc/hosts
    ├── 03-deploy-operators.sh      ← Deploy CNPG, PG clusters, Keycloak
    ├── 04-deploy-camunda.sh        ← Deploy Camunda via Helm
    ├── 05-setup-api-access.sh      ← Create api-cli client + grant roles
    ├── 06-deploy-example-process.sh ← Deploy BPMN + start instances
    ├── cleanup.sh                  ← Delete cluster + remove /etc/hosts
    ├── get-credentials.sh          ← Print credentials (-q for password only)
    ├── port-forward.sh             ← Port-forward all services (blocks)
    └── status.sh                   ← Show cluster/pod/service status
```

## Redeploying

To tear down and start fresh:

```bash
just cleanup          # Delete cluster + /etc/hosts entries
just create-cluster   # Create new cluster
just deploy           # Full deploy

# Or to re-deploy Camunda only (keeping the cluster):
helm uninstall camunda -n camunda
just deploy-camunda
```

## Troubleshooting

### Pods stuck in CrashLoopBackOff / OOMKilled

Identity, Zeebe, and Connectors are memory-hungry. Resource limits are configured in `values-no-domain.yml`. If pods are OOMKilled, increase memory limits:

```bash
# Check pod events
kubectl describe pod <pod-name> -n camunda

# Check current limits
kubectl get pod <pod-name> -n camunda -o jsonpath='{.spec.containers[*].resources}'
```

### Keycloak client issues

The `api-cli` public client requires `directAccessGrantsEnabled=true` (not `directGrantsEnabled`). If token requests fail with `invalid_grant`:

```bash
just setup-api    # Re-runs the client creation (idempotent)
```

### `/etc/hosts` required

No-domain mode requires `127.0.0.1 keycloak-service` in `/etc/hosts`. Script 02 adds it automatically. For LAN access, the script also adds `<LAN_IP> keycloak-service`. If either is missing:

```bash
echo "127.0.0.1  keycloak-service" | sudo tee -a /etc/hosts
# For LAN access (replace with your LAN IP):
echo "192.168.1.14  keycloak-service" | sudo tee -a /etc/hosts
```

### Identity returns 404 at root

Identity serves on context path `/managementidentity/`, not root. Access it at `http://localhost:8085/managementidentity/` (or `http://keycloak-service:8085/managementidentity/` for LAN access).

### Port-forward required for API access

Scripts 05 and 06 use `localhost` URLs to reach Keycloak and Zeebe. Without port-forwarding, these scripts will fail with connection errors. Always run in a separate terminal first:

```bash
just port-forward
```

### Scripts 05/06 fail with connection refused

Ensure port-forward is running and Keycloak is healthy:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/auth/
# Should return 302
```

### Cleanup fails on sudo

The cleanup script needs `sudo` to edit `/etc/hosts`. If running in a non-interactive shell (no TTY), manually remove the entry:

```bash
sudo sed -i '/keycloak-service/d' /etc/hosts
```

### Docker group permissions

If `kind` or `kubectl` fail with Docker permission errors, add your user to the docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker
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

This deletes the Kind cluster and removes `/etc/hosts` entries (requires sudo).