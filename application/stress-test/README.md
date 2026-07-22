# Stress Testing & Alerts

## Run the stress test (triggers all alerts)
```bash
kubectl apply -f stress-test/stress-test-job.yaml
kubectl -n watermark logs -f job/watermark-app-stress-test
```
Runs ~2 minutes: concurrent CPU burn, memory burn, and a stream of forced
500s — enough to trip every alert in `infra/alerts.tf`.

Clean up before re-running:
```bash
kubectl -n watermark delete job watermark-app-stress-test
```

## Optional: realistic load test (real /watermark traffic)
```bash
k6 run --vus 20 --duration 2m stress-test/k6-load-test.js \
  -e TARGET=http://$(kubectl -n watermark get ingress watermark-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

## Watch the alerts fire

**Alertmanager UI:**
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```
Open http://localhost:9093 — firing alerts show up within ~1-2 minutes of
the stress test starting (thresholds use `for: 1m`).

**Grafana:**
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```
Open http://localhost:3000 (user `admin`, password = your
`GRAFANA_ADMIN_PASSWORD`). Alerting → Alert rules shows the same rules;
the default "Kubernetes / Compute Resources / Pod" dashboard shows the
CPU/memory spike live.

**Prometheus (raw metrics/rules):**
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```
Open http://localhost:9090/alerts to see rule state (Inactive → Pending →
Firing) as the stress test runs.

## Logs (CloudWatch)
```bash
aws logs tail /eks/watermark-app-dev/watermark-app --follow
```
Or in the console: CloudWatch → Log groups →
`/eks/watermark-app-dev/watermark-app`. Every pod's stdout/stderr lands
here via Fluent Bit — including the Flask access logs generated during
the stress test.

## What each alert means
| Alert | Trips when |
|---|---|
| `WatermarkAppHighCPU` | pod CPU > 80% of its limit for 1m |
| `WatermarkAppHighMemory` | pod memory > 80% of its limit for 1m |
| `WatermarkAppCrashLooping` | container restarted 3+ times in 10m |
| `WatermarkAppHighErrorRate` | 5xx rate > 10% for 1m |
| `WatermarkAppHighLatency` | p95 request latency > 2s for 1m |
| `WatermarkAppPodDown` | zero available replicas for 1m |
