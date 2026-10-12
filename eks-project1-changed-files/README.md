# 🚀 EKS Project 1 – Production-Style CI/CD Pipeline

![AWS](https://img.shields.io/badge/AWS-EKS-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS-blue)
![Terraform](https://img.shields.io/badge/IaC-Terraform-purple)
![Docker](https://img.shields.io/badge/Container-Docker-blue)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-black)
![SonarCloud](https://img.shields.io/badge/Code%20Quality-SonarCloud-yellow)
![ECR](https://img.shields.io/badge/Registry-Amazon%20ECR-orange)
![ALB](https://img.shields.io/badge/Load%20Balancer-AWS%20ALB-red)

## 📌 Project Overview

This project demonstrates a **production-style multi-stage CI/CD pipeline** for deploying a containerized application to **Amazon EKS** using GitHub Actions.

The pipeline implements controlled promotion from:

```text
Feature → Testing → Production
```

with automated validation, Docker image management, Kubernetes deployment, AWS ALB health checks, pull requests, code-quality analysis, and production approval.

The objective is to create a controlled deployment process where:

* Feature branches are automatically validated.
* Successful feature builds create an automatic PR to `testing`.
* Testing deployment is automated after merging to `testing`.
* Successful testing creates an automatic PR to `main`.
* The `main` PR requires one reviewer.
* Production deployment requires a separate GitHub Environment approval.
* ALB and application health checks validate deployments.

---

# 🏗️ Architecture

```text
                         Developer
                             │
                             ▼
                       feature/*
                             │
                             ▼
                    ┌─────────────────┐
                    │   Feature CI    │
                    │                 │
                    │ • Unit Tests    │
                    │ • SonarCloud    │
                    │ • Docker Build  │
                    └────────┬────────┘
                             │
                             ▼
                    Automatic PR
                   feature → testing
                             │
                      0 Approvals
                             │
                             ▼
                        testing
                             │
                             ▼
                    ┌─────────────────┐
                    │   Testing CD    │
                    │                 │
                    │ • Docker Build  │
                    │ • Push to ECR   │
                    │ • Deploy EKS    │
                    │ • ALB           │
                    │ • Rollout Check │
                    │ • Health Check  │
                    └────────┬────────┘
                             │
                             ▼
                    Automatic PR
                     testing → main
                             │
                       1 Reviewer
                             │
                             ▼
                           main
                             │
                             ▼
                    ┌─────────────────┐
                    │ Production CI   │
                    │                 │
                    │ • Unit Tests    │
                    │ • SonarCloud    │
                    │ • Docker Build  │
                    │ • Push to ECR   │
                    └────────┬────────┘
                             │
                             ▼
                 Production Environment
                       Approval
                             │
                             ▼
                    ┌─────────────────┐
                    │ Production EKS  │
                    │                 │
                    │ • Deployment    │
                    │ • ALB           │
                    │ • Rollout       │
                    │ • Health Check  │
                    └─────────────────┘
```

---

# 🛠️ Technologies Used

| Category              | Technologies                  |
| --------------------- | ----------------------------- |
| Cloud                 | AWS                           |
| Kubernetes            | Amazon EKS                    |
| Infrastructure        | Terraform                     |
| Containerization      | Docker                        |
| Container Registry    | Amazon ECR                    |
| CI/CD                 | GitHub Actions                |
| Code Quality          | SonarCloud                    |
| Load Balancing        | AWS Application Load Balancer |
| Ingress               | AWS Load Balancer Controller  |
| Orchestration         | Kubernetes                    |
| Authentication        | GitHub Actions OIDC           |
| Monitoring/Validation | Kubernetes health checks      |

---

# ☁️ AWS Environment

```text
AWS Region       : ap-south-2
EKS Cluster      : eks-cluster
ECR Repository   : prod-eks-frontend
Kubernetes NS    : frontend
Deployment       : frontend
Service          : frontend
Ingress          : frontend-ingress
Health Endpoint  : /health
```

The application is deployed to Amazon EKS and exposed externally through an AWS Application Load Balancer created by the AWS Load Balancer Controller.

---

# 📂 Repository Structure

```text
EKS-Project1/
│
├── app/
│   ├── app.py
│   └── requirements.txt
│
├── Dockerfile
├── .dockerignore
├── sonar-project.properties
│
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── github-actions-role.yaml
│   └── github-actions-rolebinding.yaml
│
└── .github/
    └── workflows/
        ├── feature-ci.yml
        ├── testing-cd.yml
        └── production-cd.yml
```

This structure separates application code, Kubernetes resources, RBAC configuration, and the three CI/CD workflows.

---

# 🔄 CI/CD Pipeline

## 1️⃣ Feature CI

Triggered when code is pushed to:

```text
feature/*
```

Pipeline performs:

```text
Checkout
   ↓
Install Dependencies
   ↓
Unit Tests
   ↓
SonarCloud Analysis
   ↓
Docker Build Validation
   ↓
Automatic PR
feature/* → testing
```

The Docker image is validated during this stage but is not pushed to ECR. If the feature branch already has an open PR to `testing`, the workflow avoids creating a duplicate PR.

---

# 2️⃣ Testing CD

Triggered when the `testing` branch is updated.

```text
Merge to testing
       ↓
Docker Build
       ↓
AWS OIDC Authentication
       ↓
ECR Login
       ↓
Push Image
       ↓
Configure EKS
       ↓
Apply Kubernetes Manifests
       ↓
Update Deployment
       ↓
Rollout Validation
       ↓
ALB Health Check
       ↓
Automatic PR
testing → main
```

The Docker image is tagged using the GitHub commit SHA and pushed to Amazon ECR. Kubernetes rollout and ALB `/health` validation must succeed before the pipeline creates the production promotion PR.

---

# 3️⃣ Production CD

Triggered after changes are merged into:

```text
main
```

Pipeline:

```text
Unit Tests
    ↓
SonarCloud
    ↓
Docker Build
    ↓
Push to ECR
    ↓
Production Approval
    ↓
Deploy to EKS
    ↓
Rollout Validation
    ↓
ALB Health Check
```

Production deployment is protected using a GitHub Environment approval. The actual EKS deployment occurs only after the required approval is granted.

---

# 🔐 Security & Access

## GitHub Actions → AWS

GitHub Actions uses **OIDC authentication** to access AWS without storing long-lived AWS access keys.

Required GitHub secret:

```text
AWS_ROLE_ARN
```

Required workflow permission:

```yaml
permissions:
  contents: read
  id-token: write
```

SonarCloud requires:

```text
SONAR_TOKEN
```

The project uses a least-privilege approach for Kubernetes deployment access rather than granting `cluster-admin` to GitHub Actions.

---

# 🔑 Kubernetes RBAC

GitHub Actions authentication to AWS does **not automatically provide Kubernetes permissions**.

The project therefore uses:

```text
github-actions-role.yaml
github-actions-rolebinding.yaml
```

The recommended approach is a namespace-scoped Kubernetes `Role` with only the permissions required by the deployment pipeline.

```text
GitHub Actions
      │
      ▼
AWS OIDC
      │
      ▼
IAM Role
      │
      ▼
EKS Authentication
      │
      ▼
Kubernetes RBAC
      │
      ▼
frontend namespace
```

Cluster-wide permissions such as `kubectl get nodes` are avoided unless specifically required.

---

# ☸️ Kubernetes Deployment

The application is deployed using:

```text
Namespace      : frontend
Deployment     : frontend
Service        : frontend
Ingress        : frontend-ingress
Container      : app=frontend
Service Port   : 80
Target Port    : 5000
```

The deployment uses:

* Multiple replicas
* Rolling updates
* Readiness probes
* Liveness probes
* CPU and memory requests
* CPU and memory limits

The `/health` endpoint is used for application health validation.

---

# 🌐 AWS Application Load Balancer

The Kubernetes Ingress uses:

```yaml
ingressClassName: alb
```

AWS Load Balancer Controller creates the Application Load Balancer.

Configuration includes:

```text
Scheme        : internet-facing
Target Type   : IP
Health Path   : /health
Success Code  : 200
Ingress Name  : frontend-ingress
```

The ALB hostname can be retrieved using:

```bash
kubectl get ingress frontend-ingress -n frontend
```

The public ALB hostname is provided by the Ingress rather than the ClusterIP Service.

---

# 🌍 Health Check

Application endpoint:

```text
GET /health
```

Expected response:

```text
HTTP 200
```

The pipeline validates the endpoint through the ALB.

This provides an end-to-end validation path:

```text
Internet
   ↓
AWS ALB
   ↓
Kubernetes Ingress
   ↓
Kubernetes Service
   ↓
Frontend Pod
   ↓
/health
```

If the health check fails, the deployment pipeline fails instead of treating the deployment as successful.

---

# 🚀 Deployment Validation

Useful Kubernetes commands:

```bash
kubectl get nodes

kubectl get pods -n frontend

kubectl get deployment frontend -n frontend

kubectl get svc frontend -n frontend

kubectl get ingress frontend-ingress -n frontend

kubectl rollout status deployment/frontend -n frontend

kubectl describe ingress frontend-ingress -n frontend
```

Configure EKS access:

```bash
aws eks update-kubeconfig \
  --region ap-south-2 \
  --name eks-cluster
```

---

# 🧪 End-to-End Deployment Flow

Example:

```bash
git checkout -b feature/test-change
```

Make application changes and push:

```bash
git add .
git commit -m "test: update application"
git push origin feature/test-change
```

Expected flow:

```text
feature/test-change
        ↓
Feature CI
        ↓
Unit Tests
        ↓
SonarCloud
        ↓
Docker Validation
        ↓
Automatic PR
        ↓
testing
        ↓
Testing CD
        ↓
ECR
        ↓
EKS
        ↓
ALB
        ↓
/health = 200
        ↓
Automatic PR
        ↓
main
        ↓
1 Reviewer
        ↓
Production CI
        ↓
Production Approval
        ↓
Production EKS
        ↓
Production ALB
        ↓
/health = 200
```

---

# 📈 Autoscaling, Availability & Monitoring

| Concern | How it is handled | Where |
|---|---|---|
| Autoscaling | HPA on the `frontend` container's CPU (70% of request). Testing 1 to 2 pods, prod 2 to 6 | `k8s/base/hpa.yaml`, prod overlay |
| Voluntary disruptions | Prod PodDisruptionBudget `maxUnavailable: 1`, so a node drain evicts one pod at a time | `k8s/overlays/prod/pdb.yaml` |
| Zero-downtime deploys | `maxUnavailable: 0`, `maxSurge: 1`, readiness probe, ALB deregistration delay | prod overlay, `k8s/base/ingress.yaml` |
| AZ failure | Pods spread across zones (`topologySpreadConstraints`) | prod overlay |
| Metrics | nginx-exporter sidecar, kube-state-metrics, cAdvisor, node-exporter | `k8s/base/deployment.yaml`, `monitoring/` |
| Dashboards | Grafana "Frontend overview" (requests, connections, CPU, memory, HPA, restarts) | `monitoring/app/grafana-dashboard.yaml` |
| Alerting | Prometheus rules to Alertmanager to Slack (down, crash loop, OOM, HPA, PDB) | `monitoring/app/prometheusrule.yaml` |

The Deployment sets no `replicas`: the HPA owns the replica count, so a deploy never
resets it. The monitoring stack (kube-prometheus-stack) has its own workflow,
`.github/workflows/monitoring.yml`, behind the same `production` approval. See
[`monitoring/README.md`](monitoring/README.md) for setup, alerts and how to open Grafana.

---

# 🐛 Troubleshooting

### OIDC Authentication Error

Error:

```text
Did you mean to set the id-token permission?
```

Check:

```yaml
permissions:
  id-token: write
```

Also verify the AWS IAM OIDC trust relationship.

### Kubernetes Forbidden Error

Example:

```text
User is forbidden
```

Check:

```bash
kubectl auth can-i get pods -n frontend
```

Verify EKS access mapping and Kubernetes RoleBinding.

### ALB Hostname Missing

Check:

```bash
kubectl get ingress -n frontend

kubectl describe ingress frontend-ingress -n frontend
```

Also verify:

* AWS Load Balancer Controller
* Subnet tags
* Security groups
* IAM permissions
* Ingress configuration

### ALB 502 / 503

Check:

```bash
kubectl get pods -n frontend
kubectl get svc frontend -n frontend
kubectl describe pod -n frontend
```

Verify:

* Pod readiness
* Service selector
* Service port
* Target port
* Application listening address
* `/health` response

### ImagePullBackOff

Check:

```bash
kubectl describe pod -n frontend
```

Verify:

* ECR repository
* Image tag
* ECR permissions
* EKS image pull access

### Rollout Timeout

Run:

```bash
kubectl get pods -n frontend
kubectl describe pod -n frontend
kubectl logs -n frontend <pod-name>
```

### Automatic PR Not Created

Verify GitHub Actions has:

```yaml
permissions:
  pull-requests: write
```

Also check whether an existing open PR already exists.

---

# 🔐 Branch Protection

## Testing

```text
Pull Request Required : Yes
Required Approvals     : 0
```

## Main

```text
Pull Request Required : Yes
Required Approvals     : 1
```

Production deployment additionally requires approval from the GitHub `production` environment.

---

# 📊 Final Pipeline

| Stage             | Trigger                   | Approval            |
| ----------------- | ------------------------- | ------------------- |
| Feature CI        | Push to `feature/*`       | None                |
| Feature → Testing | Automatic PR              | 0 approvals         |
| Testing CD        | Merge to `testing`        | None                |
| Testing → Main    | Automatic PR              | 1 reviewer          |
| Production CI     | Merge to `main`           | None                |
| Production EKS    | CI + Environment approval | Production reviewer |

---

# 🎯 Key DevOps Concepts Demonstrated

This project demonstrates practical experience with:

* AWS EKS
* AWS ECR
* AWS ALB
* Kubernetes
* Docker
* GitHub Actions
* Terraform
* CI/CD automation
* GitHub OIDC
* IAM
* Kubernetes RBAC
* SonarCloud
* Kubernetes health probes
* Rolling deployments
* Automated pull requests
* Branch protection
* Production approvals
* Deployment validation
* Application health checks
* DevOps troubleshooting

---

# 📌 Project Outcome

The final implementation provides a controlled promotion path:

```text
Feature
   ↓
Automated Validation
   ↓
Testing
   ↓
Automated Deployment
   ↓
Testing Validation
   ↓
Production PR
   ↓
Reviewer Approval
   ↓
Production Approval
   ↓
Production EKS Deployment
```

This ensures that unsuccessful testing or production deployments are detected through Kubernetes rollout and ALB/application health checks before the pipeline is considered successful.

---

## 👨‍💻 Author

**Nagarajan S**

DevOps Engineer | AWS | Kubernetes | Terraform | Docker | GitHub Actions

GitHub: [@nagaraj0205](https://github.com/nagaraj0205)

