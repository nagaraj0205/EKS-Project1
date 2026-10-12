# Monitoring: Prometheus, Grafana and Alertmanager

Metrics, dashboards and alerting for the frontend on EKS, installed with the
`kube-prometheus-stack` Helm chart into the `monitoring` namespace.

```text
monitoring/
├── kube-prometheus-stack-values.yaml   Helm values (EKS-tuned: no control-plane scrapes, gp3 volumes)
├── storageclass-gp3.yaml               gp3 EBS class, applied only if "gp3" does not exist
└── app/                                applied after the Helm install (needs the operator CRDs)
    ├── kustomization.yaml
    ├── servicemonitor.yaml             scrape the nginx-exporter sidecar in prod and testing
    ├── prometheusrule.yaml             alerts: down, crash loop, OOM, restarts, HPA, PDB
    └── grafana-dashboard.yaml          "Frontend overview" dashboard (loaded by the Grafana sidecar)
```

## How the metrics flow

```text
nginx (stub_status on 127.0.0.1:8080)
   -> nginx-exporter sidecar (:9113 /metrics)
      -> Service "frontend" port "metrics"
         -> ServiceMonitor (monitoring/app) -> Prometheus -> Grafana + Alertmanager -> Slack
```

Pod CPU, memory, restarts, HPA and PDB state come from cAdvisor and
kube-state-metrics, which the chart already scrapes. Only the nginx request and
connection metrics need the sidecar.

## One-time setup

1. **EBS CSI driver** add-on on the cluster (the volumes are gp3):
   `aws eks create-addon --cluster-name eks-cluster --addon-name aws-ebs-csi-driver --region ap-south-2`
   (the add-on's service account needs the `AmazonEBSCSIDriverPolicy`).
2. **GitHub secrets**: `GRAFANA_ADMIN_PASSWORD` (required), `ALERTMANAGER_SLACK_WEBHOOK`
   (optional; without it alerts fire but are not delivered).
3. **EKS access for the pipeline**: the Helm chart installs CRDs and cluster-wide
   RBAC, so the role used by `monitoring.yml` needs cluster-admin. Use a separate
   role in the `AWS_PROD_ROLE_ARN` secret rather than widening the app-deploy role.
4. Merge to `main`. The `Monitoring` workflow runs behind the `production`
   environment approval. The first run prints the chart version it installed;
   set it as the `KPS_CHART_VERSION` repository variable to pin it.

## Opening the UIs

Nothing is exposed to the internet. Use port-forward:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# http://localhost:3000   user: admin   password: the GRAFANA_ADMIN_PASSWORD secret
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093
```

## Alerts

| Alert | Severity | Fires when |
|---|---|---|
| FrontendDown | critical | prod exporter target or nginx unreachable for 2m |
| FrontendNoReadyReplicas | critical | prod has 0 available pods for 1m |
| FrontendCrashLooping | critical | a frontend container is in CrashLoopBackOff for 5m |
| FrontendTestingDown | warning | testing target down for 10m |
| FrontendReplicasUnavailable | warning | fewer available than desired pods for 10m |
| FrontendPodRestarting | warning | more than 2 restarts in 15m |
| FrontendOOMKilled | warning | a container restarted and was last OOMKilled |
| FrontendMemoryNearLimit | warning | memory above 90% of the limit for 10m |
| FrontendHPAMaxedOut | warning | HPA at maxReplicas for 15m |
| FrontendHPANotScaling | warning | HPA cannot read metrics for 10m |
| FrontendPDBBlockingDrains | warning | prod PDB allows 0 disruptions for 30m |

Critical alerts repeat hourly and inhibit the matching warning. The built-in
`Watchdog` alert is routed to a null receiver. To confirm Slack delivery, silence
nothing and run: `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093`
then POST a test alert to `http://localhost:9093/api/v2/alerts`.

## Autoscaling and availability (k8s/)

| | testing | prod |
|---|---|---|
| HPA (CPU 70% of request, `frontend` container) | 1 to 2 pods | 2 to 6 pods |
| PodDisruptionBudget | none (1 pod would block every drain) | `maxUnavailable: 1` |
| Zone spread | none | `topologySpreadConstraints`, ScheduleAnyway |
| Rolling update | default | `maxUnavailable: 0`, `maxSurge: 1` |

The Deployment sets no `replicas`; the HPA owns the count. The HPA needs
metrics-server, which `monitoring.yml` installs if the cluster lacks it.

## Not covered (ideas for later)

- nginx `stub_status` has no per-status-code counters, so there is no 5xx error-rate
  alert. ALB 5xx and target response time are in CloudWatch (`AWS/ApplicationELB`);
  add the CloudWatch exporter (or YACE) to alert on them.
- Logs: nginx already writes JSON access logs to stdout, ready for Loki or CloudWatch Logs.
