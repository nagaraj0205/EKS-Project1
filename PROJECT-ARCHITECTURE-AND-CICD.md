# EKS React Frontend: Architecture, Manifests, and CI/CD Guide

This guide describes how the frontend is built, packaged, deployed to the
testing and production namespaces in EKS, and monitored. The YAML, Terraform,
Docker, and workflow files linked below are the executable source of truth;
the guide explains what each file contributes instead of copying all of that
code into a second place that could drift from it.

## 1. What this repository deploys

The application is a React/Vite single-page frontend. A multi-stage Docker
build compiles it to static files, and an unprivileged Nginx process serves
those files. Kubernetes runs the same image in `testing` and `prod`; the
environment-specific API URL and environment name are supplied at container
startup rather than compiled into the image.

The repository also contains Terraform for AWS infrastructure and a separate
Prometheus/Grafana workflow. It does **not** contain or deploy the application
API/middleware. In the current Kubernetes configuration `API_BASE_URL` is
empty and the Ingress sends `/api` to the frontend as well. Nginx's SPA fallback
then returns `index.html` for such a path; that is not an API implementation,
so login/API requests require an API service and routing to it before they can
work end to end.

## 2. Architecture at a glance

```text
Developer push to feature/*
  └─ GitHub Actions: lint → tests/coverage → Vite build → Docker build check
       └─ opens and auto-merges feature/* → testing (PAT/admin permissions)

Push to testing
  ├─ CI validation
  ├─ build once → immutable ECR tag = source commit SHA
  ├─ ensure AWS Load Balancer Controller is installed
  ├─ render k8s/base + testing overlay → apply to namespace testing
  ├─ wait for rollout → HTTP/runtime-config smoke tests
  └─ open/refresh testing → main promotion PR
       └─ human approval and merge

Push to main after promotion PR merge
  ├─ CI validation + SonarCloud quality gate
  ├─ production GitHub Environment approval
  ├─ resolve the merged testing PR's tested commit SHA
  ├─ verify its existing ECR image; do not rebuild it
  └─ render k8s/base + prod overlay → apply to namespace prod

Browser → public AWS ALB → NodePort Service → ready frontend pod:3000
                                              ├─ Nginx static SPA
                                              └─ Nginx Prometheus exporter

Prometheus → exporter sidecar metrics endpoint (both app namespaces)
Grafana ← Prometheus / Kubernetes metrics
```

### AWS and Kubernetes layers

1. **Network and cluster:** Terraform creates a VPC across three available
   Availability Zones, public and private subnets, NAT, an EKS cluster, and a
   managed node group. Nodes run in private subnets. The EKS API endpoint is
   enabled for public and private access.
2. **Image registry:** Terraform creates the ECR repository with immutable
   image tags and scan-on-push enabled. The application workflow pushes one
   image per `testing` commit, tagged with that commit SHA.
3. **Ingress/load balancing:** The AWS Load Balancer Controller watches
   Kubernetes Ingress resources and provisions an internet-facing ALB for each
   environment. The ALB sends traffic to worker-node NodePorts, which forward
   to ready frontend pods.
4. **Application:** A Deployment starts the Nginx frontend and an exporter
   sidecar in each pod. A Service selects those pods; readiness probes gate
   traffic, and an HPA scales the number of replicas.
5. **Observability:** kube-prometheus-stack provides Prometheus, Grafana,
   Alertmanager, kube-state-metrics, and node-exporter. A ServiceMonitor
   configures scraping of the Nginx exporter. Dashboard and alert resources
   are applied separately.

## 3. Repository file map

### Application and container

| File | Role |
|---|---|
| [Dockerfile](./Dockerfile) | Multi-stage Node build and unprivileged Nginx runtime image. |
| [nginx.conf](./nginx.conf) | Port 3000 static server, SPA fallback, health endpoint, headers, caching, JSON stdout access logs, and loopback-only exporter status endpoint. |
| [docker-entrypoint.sh](./docker-entrypoint.sh) | Escapes and writes runtime environment values to `runtime-config.js`, then execs Nginx. |
| [public/runtime-config.js](./public/runtime-config.js) | Development/default config copied into the Vite bundle and replaced in a running container. |
| [src/config.js](./src/config.js) | Reads browser runtime config and exposes API base URL, app environment, API prefix, and storage key names. |
| [vite.config.js](./vite.config.js) | React build, local `/api` proxy, chunk splitting, and Vitest/coverage configuration. |
| [package.json](./package.json) | Node scripts and pinned frontend/test dependencies; `package-lock.json` is used by `npm ci`. |
| [.env.example](./.env.example) | Example local runtime values only; these values are public browser configuration, not secrets. |
| [sonar-project.properties](./sonar-project.properties) | SonarCloud project metadata, source/test paths, and LCOV report location. |

### Active Kubernetes manifests

The application workflow renders the Kustomize overlays, not the standalone
files in the `k8s` directory root.

| File | Role and effective behavior |
|---|---|
| [k8s/base/kustomization.yaml](./k8s/base/kustomization.yaml) | Includes shared ConfigMap, Deployment, Service, Ingress, and HPA. |
| [k8s/base/deployment.yaml](./k8s/base/deployment.yaml) | Frontend container with image placeholder, ConfigMap env, named port 3000, `/healthz` liveness/readiness probes, resource requests/limits, `/tmp/nginx` writable volume, and non-root Nginx exporter sidecar. No replica count is set because the HPA owns scaling. |
| [k8s/base/service.yaml](./k8s/base/service.yaml) | NodePort Service routes port 80 to frontend port 3000 and exposes exporter port 9113 for Prometheus scraping. |
| [k8s/base/configmap.yaml](./k8s/base/configmap.yaml) | Defaults `API_BASE_URL` to empty and `APP_ENV` to `dev`; environment overlays replace `APP_ENV`. |
| [k8s/base/ingress.yaml](./k8s/base/ingress.yaml) | `alb` Ingress class, internet-facing instance targets, HTTP listener, `/healthz` ALB health check, and frontend Service backend. |
| [k8s/base/hpa.yaml](./k8s/base/hpa.yaml) | CPU utilization target is 70%; base range is 1–2 replicas. Scale-up is responsive; scale-down waits 300 seconds and removes at most one pod per 60 seconds. |
| [k8s/overlays/testing/kustomization.yaml](./k8s/overlays/testing/kustomization.yaml) | Adds the `testing` namespace, testing ingress patch, and `APP_ENV=testing`. |
| [k8s/overlays/testing/namespace.yaml](./k8s/overlays/testing/namespace.yaml) | Creates namespace `testing` with an environment label. |
| [k8s/overlays/testing/ingress-patch.yaml](./k8s/overlays/testing/ingress-patch.yaml) | Names/tags the dedicated testing ALB. |
| [k8s/overlays/prod/kustomization.yaml](./k8s/overlays/prod/kustomization.yaml) | Adds the `prod` namespace and PDB; sets `APP_ENV=prod`; applies safe rolling update, zone-spread preference, and production HPA range. |
| [k8s/overlays/prod/namespace.yaml](./k8s/overlays/prod/namespace.yaml) | Creates namespace `prod` with an environment label. |
| [k8s/overlays/prod/ingress-patch.yaml](./k8s/overlays/prod/ingress-patch.yaml) | Names/tags the production ALB. HTTPS annotations are documented in comments and require an ACM certificate and DNS configuration before enabling. |
| [k8s/overlays/prod/pdb.yaml](./k8s/overlays/prod/pdb.yaml) | PodDisruptionBudget limits voluntary disruptions to one unavailable frontend pod. |

The production overlay sets the HPA range to 2–6. It adds a rolling-update
strategy with `maxUnavailable: 0` and `maxSurge: 1`, and asks Kubernetes to
spread pods across zones when possible (`ScheduleAnyway` is a preference, not a
hard guarantee).

### Monitoring manifests

| File | Role |
|---|---|
| [monitoring/kube-prometheus-stack-values.yaml](./monitoring/kube-prometheus-stack-values.yaml) | Helm values for resource sizing, persistent storage, retention, selectors, Grafana secret keys, and dashboard sidecar. Disables control-plane component scrapes that are not available/appropriate in this EKS setup. |
| [monitoring/storageclass-gp3.yaml](./monitoring/storageclass-gp3.yaml) | Encrypted gp3 EBS StorageClass using the EBS CSI provisioner, delayed binding, expandable volumes, and `Delete` reclaim policy. |
| [monitoring/app/kustomization.yaml](./monitoring/app/kustomization.yaml) | Bundles the application ServiceMonitor, PrometheusRule, and Grafana dashboard ConfigMap into namespace `monitoring`. |
| [monitoring/app/servicemonitor.yaml](./monitoring/app/servicemonitor.yaml) | Scrapes Service port `metrics`, endpoint `/metrics`, every 30 seconds from namespaces `prod` and `testing`. |
| [monitoring/app/prometheusrule.yaml](./monitoring/app/prometheusrule.yaml) | Production alerts for missing/down frontend metrics, unavailable replicas, and an HPA at its maximum. |
| [monitoring/app/grafana-dashboard.yaml](./monitoring/app/grafana-dashboard.yaml) | Dashboard ConfigMap discovered by the Grafana sidecar label; charts request rate, active connections, CPU, and available replicas. |
| [monitoring/README.md](./monitoring/README.md) | Monitoring prerequisites, install/access instructions, and HPA notes. |

The Helm values request persistent gp3 volumes: Prometheus 20 GiB with seven
days of retention (plus a 17 GB retention-size cap), Alertmanager 2 GiB, and
Grafana 5 GiB. The workflow requires the EBS CSI driver to be ready before
installing these workloads. Alertmanager is installed, but this repository
does not configure external notification receivers.

### Infrastructure and workflows

| File | Role |
|---|---|
| [terraform/main.tf](./terraform/main.tf) | VPC, EKS, managed node group, EBS CSI driver IAM role/add-on, and ECR resources. |
| [terraform/variables.tf](./terraform/variables.tf) | Region, cluster, network, node sizing, and registry input definitions/defaults. |
| [terraform/provider.tf](./terraform/provider.tf) | AWS provider and common resource tags. |
| [terraform/versions.tf](./terraform/versions.tf) | Terraform/provider version constraints. |
| [terraform/outputs.tf](./terraform/outputs.tf) | Cluster, VPC, subnet, ECR, and kubectl configuration outputs. |
| [terraform/terraform.tfvars.example](./terraform/terraform.tfvars.example) | Example input file; copy and adjust for your own environment. |
| [.github/workflows/ci.yml](./.github/workflows/ci.yml) | Application checks, image publication, ALB controller installation, testing/prod deployment and promotion. |
| [.github/workflows/monitoring.yml](./.github/workflows/monitoring.yml) | Monitoring validation and main-branch monitoring deployment. |
| [.github/scripts/install-alb-controller.sh](./.github/scripts/install-alb-controller.sh) | Helm install/upgrade of the AWS Load Balancer Controller, including required pre-existing IRSA ServiceAccount verification. |

The Terraform state and local `.tfvars` are intentionally not part of this
guide. Treat state as sensitive, keep it out of source control, and use a
protected remote backend with locking for shared/production use.

## 4. How the runtime configuration works

1. `npm run build` creates static assets. The API URL is **not** compiled into
   the JavaScript bundle.
2. The image's `public/runtime-config.js` provides local dev/preview defaults.
3. Kubernetes injects every `frontend-config` ConfigMap entry as an environment
   variable using `envFrom`.
4. On each container start, `docker-entrypoint.sh` writes those values into
   `/usr/share/nginx/html/runtime-config.js`; its escaping protects JavaScript
   string literals from quotes and backslashes in configuration.
5. The browser loads that file and `src/config.js` reads
   `window.__APP_CONFIG__`. Empty `apiBaseUrl` means same-origin requests.
6. `nginx.conf` serves the frontend on port 3000. `/healthz` returns `ok`,
   hashed `/assets/` files receive immutable caching, and `index.html` and
   `runtime-config.js` are not cached so deploys/runtime settings take effect.

Changing a ConfigMap by itself does not restart existing pods. Roll out/restart
the Deployment after changing runtime values. Do not put secrets in this
ConfigMap or in `runtime-config.js`: values sent to the browser are public.

## 5. Application CI/CD workflow, stage by stage

The complete pipeline definition is
[.github/workflows/ci.yml](./.github/workflows/ci.yml). Its fixed settings are
AWS region `ap-south-2`, EKS cluster `eks-cluster`, ECR repository
`prod-eks-frontend`, and ALB Controller chart version `3.5.0`.

### Triggers and branch rules

- Pushes to `feature/**`, `testing`, and `main` start the workflow.
- Pull requests **into `main`** start it. Despite a comment in the workflow
  mentioning PRs into `testing` too, the actual trigger only lists `main`.
- `workflow_dispatch` starts CI, but the deploy jobs are guarded by push/ref
  conditions, so manually running this workflow does not itself deploy the
  application.
- `enforce-source-branch` fails PRs into `main` unless the source is `testing`.

### Job 1: CI Validation

Runs on the GitHub-hosted Ubuntu runner:

1. Checks out full Git history (`fetch-depth: 0`) for SonarCloud blame/new-code
   analysis.
2. Installs Node 22 and uses npm's cache.
3. Installs exactly the lockfile dependency graph with `npm ci`.
4. Runs `npm run lint`.
5. Runs `npm run test:coverage`, which runs Vitest and writes LCOV coverage.
6. Runs `npm run build` to verify the production frontend build.
7. On a push to `main` only, runs SonarCloud and waits up to 300 seconds for
   the quality gate. A failed gate fails CI and blocks the production job.
8. Runs `docker build` as an image-build validation. This is not pushed; the
   actual deployable image is built in the `docker` job on `testing`.

### Job 2: feature branch promotion to testing

After CI succeeds for a feature-branch push, `create-testing-pr` uses the
`AUTOMATION_MERGE_PAT` token to check for commits ahead of `testing`, create or
reuse a feature-to-testing PR, and merge it using `gh pr merge --admin`.
Consequently this automation depends on a PAT with the necessary repository
permissions and admin/bypass rights. It is configured for automatic promotion,
not a human approval step.

### Job 3: build and push the candidate image

Only a push to `testing` runs `docker`:

1. Assumes the AWS role from `AWS_ROLE_ARN` via GitHub OIDC.
2. Logs into ECR.
3. Constructs
   `<ECR registry>/prod-eks-frontend:<github SHA>`.
4. Builds the Dockerfile and pushes that image.

The ECR tag is the exact testing commit SHA; ECR's immutable-tag setting
prevents overwriting the tag. This job output is passed to deploy and
validation jobs.

### Job 4: install/upgrade the ALB controller

On pushes to `testing` or `main`, the workflow configures AWS credentials and
kubectl, then calls
[.github/scripts/install-alb-controller.sh](./.github/scripts/install-alb-controller.sh).
The script verifies that the `aws-load-balancer-controller` ServiceAccount
already has an IRSA role annotation from the same AWS account, discovers the
cluster VPC, installs/upgrades the pinned Helm chart, verifies the webhook TLS
secret, updates the controller's certificate checksum annotation, and waits
for its Deployment rollout.

This script does **not** create the controller's IAM policy, role, OIDC trust,
or ServiceAccount; those must be provisioned separately. Terraform in this
repository creates the EBS CSI role/add-on, not the ALB controller role.

### Job 5: deploy to testing

Requires both the image push and controller installation to succeed:

1. Configures AWS credentials and EKS kubeconfig.
2. Runs `kubectl kustomize k8s/overlays/testing`.
3. Replaces `IMAGE_PLACEHOLDER` with the exact ECR image and fails if any
   placeholder remains.
4. Applies the rendered namespace, Deployment, Service, Ingress, and HPA.
5. Waits up to 300 seconds for the frontend Deployment rollout.
6. Polls the Ingress for its ALB hostname and records the testing URL.

### Job 6: post-deploy testing validation

Requires testing deployment to finish:

1. Confirms the Deployment's image reference exactly matches the image output
   from the build job.
2. Port-forwards the testing Service and checks `/healthz` returns `ok`.
3. Checks `/` and a client-side deep route both return HTTP 200.
4. Reads `/runtime-config.js` and asserts `appEnv` is `testing`.

If these checks pass, `create-prod-pr` opens or refreshes a PR from `testing` to
`main`, recording the tested image reference in the PR body. This is the
promotion gate; the main branch should receive the testing changes through
this PR.

### Job 7: production deployment

Runs after a push to `main` and successful CI/controller jobs. The
`production` GitHub Environment can require reviewers before the job proceeds.

1. Uses GitHub's API to find the `testing` → `main` PR associated with the main
   commit and resolves the source testing commit SHA. It fails closed if the
   main commit did not come from that promotion PR.
2. Assumes the AWS role, logs into ECR, and verifies the SHA-tagged image
   already exists.
3. Does **not** run `docker build` or push another image. It uses the image
   built and tested in stage 3.
4. Renders `k8s/overlays/prod`, replaces the placeholder with the tested image,
   and applies the rendered resources.
5. Waits for rollout, reports the production ALB hostname, and checks
   `/healthz` plus `appEnv=prod`.
6. On failure after the apply step was run, attempts `kubectl rollout undo`
   and waits for the rollback rollout. The rollback commands are best-effort
   (`|| true`); check the job logs and Deployment revision if rollback itself
   fails.

This design promotes the same image digest/tag from testing to production
rather than rebuilding different bytes for production.

## 6. Monitoring workflow, stage by stage

The workflow is
[.github/workflows/monitoring.yml](./.github/workflows/monitoring.yml).
Changes under `monitoring/**`, `k8s/**`, `nginx.conf`, or the monitoring
workflow trigger validation on PRs and pushes to the configured branches.
`workflow_dispatch` is also available. The deploy job only runs for a push to
`main` or a manual dispatch from `main`.

### Validation job

1. Installs Helm and Python.
2. Renders both application overlays and `monitoring/app` with Kustomize.
3. Parses the rendered application YAML and checks that Deployment replicas
   are not hard-coded, HPA CPU target is 70%, production HPA range is 2–6, and
   production includes a PDB.
4. Parses the Grafana dashboard JSON embedded in the ConfigMap.
5. Renders kube-prometheus-stack using the repository's Helm values.

### Deploy job

After validation, the main-branch deploy job requires the `production`
environment and serializes deployments:

1. Requires GitHub secret `GRAFANA_ADMIN_PASSWORD`.
2. Assumes `AWS_PROD_ROLE_ARN`, falling back to `AWS_ROLE_ARN`, then configures
   kubectl for EKS.
3. Ensures metrics-server exists so the HPA has Kubernetes metrics.
4. Ensures the `gp3` StorageClass exists and checks EBS CSI controller/node
   workloads are available. It fails with an actionable error if the CSI
   driver is missing.
5. Creates namespace `monitoring` and applies Secret `grafana-admin` from the
   GitHub secret. The secret contains the Grafana admin username/key expected
   by the Helm values; the password itself is not stored in this repository.
6. Installs/upgrades `kube-prometheus-stack`. It uses repository variable
   `KPS_CHART_VERSION` when set; otherwise it selects the latest version found
   by Helm at deployment time. `--atomic` and a timeout are used.
7. Waits for the operator, Grafana, Prometheus, and Alertmanager workloads.
8. Server-side dry-runs and applies the ServiceMonitor, alert rules, and
   dashboard ConfigMap.
9. Prints monitoring resource status and port-forward commands in the Actions
   summary. Monitoring services are internal ClusterIP services, not public
   Ingresses.

See [monitoring/README.md](./monitoring/README.md) for Grafana/Prometheus
port-forward commands and HPA inspection commands.

## 7. Terraform bootstrap and first deployment

Terraform is the infrastructure bootstrap layer; GitHub Actions deploys
application and monitoring Kubernetes resources after the cluster exists.

1. Install/configure AWS CLI, Terraform (>= 1.6), kubectl, Helm, and Docker.
   Ensure the AWS identity used for Terraform can create VPC, EKS, IAM, ECR,
   and EKS add-on resources.
2. Review [terraform/variables.tf](./terraform/variables.tf) and
   [terraform/terraform.tfvars.example](./terraform/terraform.tfvars.example).
   Create a private local `terraform/terraform.tfvars` with your intended
   values. The checked-in example is a template, not production-ready sizing.
3. From `terraform/`, run:

   ```sh
   terraform init
   terraform fmt -check
   terraform validate
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

4. Capture outputs, especially `cluster_name`, `ecr_repository_url`, and
   `configure_kubectl`; configure kubectl with the output command.
5. Configure GitHub OIDC trust and an IAM role for Actions. Set repository
   secret `AWS_ROLE_ARN` (and, if needed, `AWS_PROD_ROLE_ARN`). Grant only the
   AWS permissions required by the workflow. The IAM role must also be granted
   appropriate EKS access; Terraform grants cluster creator admin permissions
   only to the principal applying Terraform.
6. Provision the separate AWS Load Balancer Controller IRSA policy/role and
   annotated `kube-system/aws-load-balancer-controller` ServiceAccount required
   by the install script.
7. Configure repository secret `AUTOMATION_MERGE_PAT` with the repository
   access and merge permissions required by feature promotion. Configure
   `SONAR_TOKEN` for SonarCloud analysis on `main`.
8. Configure branch protections/required checks and the GitHub `production`
   Environment reviewers to match the intended approval process. For
   monitoring, add `GRAFANA_ADMIN_PASSWORD`; optionally set
   `KPS_CHART_VERSION` as a repository variable to pin the chart.
9. Push a `feature/*` branch, verify CI and automatic promotion, and then
   observe testing image publication, deployment, and smoke checks.
10. Review and approve the generated `testing` → `main` release PR. After it is
    merged, approve the production Environment job if required and inspect the
    deployment/URL/smoke-test results.
11. Deploy monitoring by merging monitoring changes to `main` or manually
    running **Monitoring (Prometheus + Grafana)** against `main`.

The Terraform defaults and example node types are for demonstration and must
be reviewed for workload capacity, availability, and cost before production.
In particular, `cluster_endpoint_public_access_cidrs` is currently
`0.0.0.0/0`; restrict it to trusted CIDRs in a real deployment. The current
network configuration uses a single NAT gateway, which is a cost/availability
tradeoff rather than a fully redundant NAT-per-AZ design.

## 8. Manifest rendering and day-to-day operations

Render the effective manifests locally before applying:

```sh
kubectl kustomize k8s/overlays/testing
kubectl kustomize k8s/overlays/prod
kubectl kustomize monitoring/app
```

Render the Helm chart in PowerShell:

```powershell
helm template monitoring prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  -f monitoring/kube-prometheus-stack-values.yaml
```

In Bash, replace PowerShell backticks with `\` at the end of each continued
line.

The application Deployment contains `IMAGE_PLACEHOLDER` intentionally. Before
applying an application overlay manually, substitute it with a real image
reference as the workflow does, and verify that no placeholder remains.

Useful checks:

```sh
kubectl get namespaces
kubectl -n testing get deploy,pods,svc,ingress,hpa
kubectl -n prod get deploy,pods,svc,ingress,hpa,pdb
kubectl -n monitoring get pods,servicemonitor,prometheusrule
kubectl -n prod describe deployment frontend
kubectl -n prod logs deployment/frontend -c frontend
kubectl -n prod logs deployment/frontend -c nginx-exporter
```

To access monitoring without exposing it publicly:

```sh
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093
```

## 9. Important scope and configuration notes

- **Standalone YAML is not the deploy path:** `k8s/deployment.yaml`,
  `k8s/service.yaml`, and `k8s/configmap.yaml` are standalone alternatives not
  referenced by the workflows. The workflows use `k8s/overlays/testing` and
  `k8s/overlays/prod`, which share `k8s/base`. Do not use the top-level
  Deployment as a substitute: it has a fixed replica count and lacks the
  current sidecar/security/rollout setup.
- **No backend in this repository:** the UI can render and serve successfully,
  but API functionality needs a backend service and routing rule. The current
  Ingress sends all paths to the frontend Service.
- **Autoscaling prerequisites:** the HPA needs metrics-server, CPU requests,
  and functioning Kubernetes metrics. The monitoring workflow installs
  metrics-server when absent; the application workflow does not.
- **Persistent volumes require AWS plumbing:** the monitoring chart needs
  EBS CSI and the encrypted `gp3` StorageClass. EBS volumes incur AWS storage
  and I/O charges.
- **TLS is not enabled by default:** the Ingress listens on HTTP port 80.
  Enable HTTPS only after providing an ACM certificate in the cluster region,
  DNS pointing to the ALB, and the HTTPS/redirect annotations.
- **Access and secret setup is external:** GitHub OIDC roles, EKS access,
  ALB-controller IRSA setup, repository secrets, branch protection, and
  environment reviewers must be configured in AWS/GitHub; they are not all
  created by the checked-in Terraform.
- **Do not commit generated or sensitive files:** keep `.env`, local
  `terraform.tfvars`, Terraform state/plan files, credentials, and generated
  kubeconfig out of source control.
- **Existing state is already tracked:** this checkout has tracked Terraform
  state and backup files. Do not commit local edits to them; migrate state to a
  protected remote backend and handle removing tracked state files as a
  separate, reviewed change.
