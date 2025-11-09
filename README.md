# Acquisitions API – Local Dev and Kubernetes Deploy

This repository contains a Node.js/Express API, Docker assets, and Kubernetes manifests (with Kustomize overlays) for local development and production deployment.

## Contents

- Quick start
- Development options
  - Docker Compose
  - Minikube + Kubernetes (recommended for parity)
- Secrets management (safe-by-default)
- Kubernetes layout (base, local, prod)
- Scripts
- CI/Pre-commit secret scanning
- Troubleshooting

---

## Quick start

Prereqs:

- Docker
- kubectl
- Optional: Minikube (for local Kubernetes)
- PowerShell or bash for scripts

Clone and install deps (if you want to run Node scripts locally):

```bash
npm ci
```

Run with Docker Compose (simplest):

```bash
# Development (hot reload + Neon Local via docker-compose)
docker compose -f docker-compose.dev.yml up --build
```

Run with Minikube (Kubernetes, recommended for deploy parity):

```powershell
# Build, enable Minikube addons, create secrets, deploy, and port-forward
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
```

---

## Development options

### Option A: Docker Compose (local-only)

- File: `docker-compose.dev.yml`
- Brings up:
  - `neon-local` (Neon local proxy)
  - `app` (development target, hot reload)
- Logs under `./logs` are mounted to the container.

Start:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Stop:

```bash
docker compose -f docker-compose.dev.yml down
```

### Option B: Minikube + Kubernetes (local cluster)

This mirrors prod more closely (Ingress, HPA, PVC, etc.).

1. Start Minikube and enable addons

```powershell
minikube start --driver=docker
minikube addons enable ingress
minikube addons enable metrics-server
```

2. Create required secrets (local defaults + Neon credentials)

```powershell
# Interactive (prompts if env vars missing)
.\scripts\create-secrets.ps1

# Or non-interactive
$env:NEON_PROJECT_ID = "<your_neon_project_id>"
$env:NEON_API_KEY    = "<your_neon_api_key>"
$env:DATABASE_URL    = 'postgres://neon:neon@neon-local:5432/neondb'
$env:ARCJET_KEY      = 'ajkey_local_dev'
.\scripts\create-secrets.ps1 -NonInteractive
```

3. Deploy locally (script builds image and loads into Minikube)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
```

4. Access the API

- Port-forward (done by the script): http://localhost:8080/
- Ingress (optional): map `acquisitions.local` to `minikube ip` in your hosts file, then open http://acquisitions.local/

---

## Secrets management (safe-by-default)

- Do NOT commit real secrets.
- Kubernetes Secrets are created at deploy time via scripts or CI/CD.
- In Git:
  - `k8s/base/secret.yaml` contains placeholders (safe to commit).
  - `k8s/overlays/local/secret-local.yaml` contains non-sensitive local defaults (safe to commit).
  - `neon-local-secret` (with `NEON_PROJECT_ID`/`NEON_API_KEY`) is NOT in Git and must be created in the cluster.

Prod guidance:

- Inject `DATABASE_URL`, `ARCJET_KEY`, etc. from CI secrets and create/update the Kubernetes Secret in the prod namespace before or as part of deploy.
- Consider SOPS + age or External Secrets Operator for GitOps workflows.

---

## Kubernetes layout

- Base: `k8s/base` (shared across environments)
  - `deployment.yaml`, `service.yaml`, `configmap.yaml`, `secret.yaml`, `hpa.yaml`, `pvc-logs.yaml`, `namespace.yaml`, `ingress.yaml` (example)
- Local overlay: `k8s/overlays/local`
  - Patches the base (dev config, safe secrets, replica/resources tuned for local)
  - Adds `neon-local.yaml` (Neon proxy in-cluster) and `ingress-local.yaml`
  - Sets HPA to 1 replica to avoid metrics dependency
- Prod overlay: `k8s/overlays/prod`
  - Sets image policy to `Always` and includes prod ingress
  - You must set your real image repo/tag and create real Secrets in the `acquisitions` namespace

Apply overlays:

```bash
# Local
kubectl apply -k k8s/overlays/local

# Prod
kubectl apply -k k8s/overlays/prod
```

---

## Scripts

- `scripts/deploy-local.ps1`
  - Builds `muiruridennis/acquisitions:latest` and loads into Minikube
  - Enables Minikube addons (ingress, metrics-server)
  - Ensures namespace and creates `neon-local-secret` if missing
  - Applies `k8s/overlays/local`
  - Waits for `neon-local`, then `acquisitions-app`
  - Port-forwards `service/acquisitions-app` to `http://localhost:8080`

- `scripts/create-secrets.ps1`
  - Creates/updates:
    - `neon-local-secret` with `NEON_PROJECT_ID` and `NEON_API_KEY`
    - `acquisitions-app-secret` with `DATABASE_URL` and `ARCJET_KEY` (safe local defaults if not provided)

- `scripts/dev.ps1` / `scripts/dev.sh`
  - A convenience for Docker Compose dev mode

- `scripts/prod.ps1` / `scripts/prod.sh`
  - Compose-based production run (single host), not Kubernetes

---

## CI/Pre-commit secret scanning

- `.gitignore` excludes `.env`, `.env.*` (except `.env.example`), `node_modules/`, `logs/`, build artifacts, and editor/OS files.
- `.gitleaks.toml` allows only benign local/test values.
- Optional pre-commit hook:

```bash
# Enable repository hooks
git config core.hooksPath scripts/git-hooks

# Install gitleaks (https://github.com/gitleaks/gitleaks)
# Then commits will be scanned automatically
```

Manual scan:

```bash
gitleaks detect --no-banner --redact
```

---

## Troubleshooting

- ImagePullBackOff (local):
  - Ensure the image is built and loaded into Minikube:
    ```bash
    docker build -t muiruridennis/acquisitions:latest .
    minikube image load muiruridennis/acquisitions:latest --overwrite
    ```

- CreateContainerConfigError: secret not found:
  - `neon-local-secret` missing → run `scripts/create-secrets.ps1` or create manually.

- CrashLoopBackOff with `REPLACE_WITH_PROD_DATABASE_URL`:
  - App used base placeholder secret → ensure `acquisitions-app-secret` exists in the correct namespace.

- Deployment exceeded progress deadline:
  - Check pod events (`kubectl describe pod ...`).
  - Local overlay increases memory to avoid OOM; tweak further if needed.

- Ingress not reachable:
  - `minikube addons enable ingress`
  - Add hosts entry: `$(minikube ip) acquisitions.local` or use port-forward.

---

## Testing & linting

```bash
npm test
npm run lint
npm run lint:fix
npm run format
```

---

## Production notes (Kubernetes)

1. Build and push an image you control:

```bash
docker build -t <registry>/<org>/acquisitions:<tag> -f Dockerfile --target production .
docker push <registry>/<org>/acquisitions:<tag>
```

2. Update `k8s/overlays/prod/kustomization.yaml` image name/tag.

3. Create prod secrets in namespace `acquisitions` before applying:

```bash
kubectl create namespace acquisitions --dry-run=client -o yaml | kubectl apply -f -
kubectl -n acquisitions create secret generic acquisitions-app-secret \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=ARCJET_KEY="${ARCJET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

4. Deploy:

```bash
kubectl apply -k k8s/overlays/prod
```

---

## License

MIT (or project’s license).
