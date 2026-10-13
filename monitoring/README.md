# Prometheus and Grafana

This repo installs `kube-prometheus-stack` into the `monitoring` namespace. It
includes Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter.
Prometheus scrapes the Nginx exporter sidecar in both app namespaces; Grafana
loads the frontend dashboard from a ConfigMap.

## Prerequisites

- An EKS cluster named `eks-cluster` in `ap-south-2`.
- The AWS EBS CSI driver add-on, with permission to provision encrypted EBS
  volumes. The workflow creates a `gp3` StorageClass for the stack's persistent
  data.
- GitHub Actions OIDC access to EKS. The role needs cluster-wide permissions to
  install Helm chart CRDs and cluster-scoped resources. Set the repository
  secret `AWS_PROD_ROLE_ARN` to a suitably privileged role; if unset, the
  workflow uses the existing `AWS_ROLE_ARN`.
- A GitHub secret named `GRAFANA_ADMIN_PASSWORD`.
- The GitHub `production` environment, if deployment approval is desired.

## Install

Merge the changes into `main` or run the **Monitoring (Prometheus + Grafana)**
workflow manually from `main`. It installs metrics-server for HPA metrics if
the cluster does not already expose the Kubernetes metrics API, installs the
monitoring chart, then applies the ServiceMonitor, alerts, and dashboard.

The chart version can be pinned by setting repository variable
`KPS_CHART_VERSION` to a version listed by:

```sh
helm search repo prometheus-community/kube-prometheus-stack
```

## Access

Grafana, Prometheus, and Alertmanager use internal `ClusterIP` Services; they
are not exposed through the public application Ingress. Use port-forwarding:

```sh
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093
```

Open Grafana at <http://localhost:3000> and sign in as `admin` with the password
stored in `GRAFANA_ADMIN_PASSWORD`. The **Frontend overview** dashboard shows
Nginx request rate and connections, frontend CPU, and available replicas.
Prometheus alert rules report production scrape failures, unavailable replicas,
and an HPA that remains at its maximum. Alertmanager is installed, but external
notification routing is not configured.

## Autoscaling

The HPA scales on average CPU utilization at 70% of the requested CPU. Testing
scales from 1 to 2 pods; production scales from 2 to 6. The deployment does not
set a replica count so apply/rollout operations do not reset the HPA's scaling
decisions. Production's PDB allows at most one voluntary disruption at a time.

Check operation with:

```sh
kubectl get hpa -A
kubectl -n monitoring get servicemonitor,prometheusrule
kubectl -n monitoring get pods
```
