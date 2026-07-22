# Watermark App — CI/CD + GitOps Demo

A tiny Flask service that adds a watermark to uploaded images. Built to
exercise a full CI/CD + GitOps pipeline: tests → SonarCloud → Docker
multi-stage build → Trivy scan → ArgoCD → EKS → monitoring.

## App

- `POST /watermark` — form field `image`, returns watermarked PNG
- `GET /healthz` — liveness
- `GET /readyz` — readiness (503 until the watermark logo asset exists)

Run locally:
```bash
pip install -r requirements-dev.txt
python app.py
curl -F "image=@sample.jpg" http://localhost:8080/watermark -o out.png
```

## Docker (multi-stage)

- **builder** — installs Python deps into `/install`
- **test** — installs dev deps, copies source, runs `pytest`. CI runs
  `docker build --target test` so a failing test fails the image build.
- **runtime** — slim final image, non-root user, only runtime shared libs

```bash
docker build --target test .          # run tests in a container
docker build --target runtime -t watermark-app:local .
```

## Init container pattern

The watermark logo isn't baked into the image — it's pulled from S3 by an
`initContainer` (`fetch-watermark-asset`) into a shared `emptyDir` volume
that the app container also mounts at `/app/assets`. This means you can
rotate the logo without rebuilding/redeploying the app image, and
`/readyz` won't pass until the asset is actually staged.

(A sidecar variant would work too: run a container alongside the app that
watches an input folder and drops watermarked copies into an output
folder shared over a volume — useful if you want to decouple watermarking
from the HTTP layer entirely.)

## Pipeline (`.github/workflows/ci.yaml`)

1. **test** — pytest + coverage
2. **sonarcloud** — scan + quality gate (blocks pipeline on failure)
3. **build-scan-push** — build test stage, build runtime image, Trivy
   scan (fails on HIGH/CRITICAL), push to ECR
4. **update-gitops** — bumps `newTag` in the separate GitOps repo's
   `kustomization.yaml`, which ArgoCD is watching

## GitOps / ArgoCD

`k8s/argocd-application.yaml` defines an `Application` with
`automated: { prune: true, selfHeal: true }` pointed at the GitOps repo's
`envs/dev` path. ArgoCD reconciles the cluster to match git on every
change and on drift.

## EKS exposure

`k8s/ingress.yaml` creates a public ALB with `scheme: internet-facing` and
**no custom domain required** — AWS gives every ALB a free, public DNS
name automatically. Find it after ArgoCD syncs:
```bash
kubectl -n watermark get ingress watermark-app
# ADDRESS column: k8s-watermark-xxxxxxxx-yyyyyyyy.us-east-1.elb.amazonaws.com
```
That URL works immediately over plain HTTP from anywhere on the internet.
If you later get a real domain, point a Route53 CNAME/ALIAS at that ALB
hostname, then switch the Ingress to port 443 with an ACM cert.

Monitoring UIs (Grafana/Prometheus) should instead use an **internal**
ALB/NLB (`alb.ingress.kubernetes.io/scheme: internal`) or be reached via
port-forward/VPN, so they stay off the public internet.

## Monitoring

Install `kube-prometheus-stack` via Helm for Prometheus + Grafana +
Alertmanager (done automatically by `infra/addons.tf`). The app exposes
`/metrics` via `prometheus-flask-exporter`, scraped through a
ServiceMonitor. `infra/alerts.tf` defines alert rules for CPU, memory,
crash loops, error rate, and latency.

## Logs

Fluent Bit ships every pod's stdout/stderr to CloudWatch Logs
(`infra/logging.tf`), authenticated via IRSA — no static keys. View with:
```bash
aws logs tail /eks/watermark-app-dev/watermark-app --follow
```

## Stress testing / triggering alerts

See `stress-test/README.md` — a Job that burns CPU/memory and forces
errors to trip every alert, plus an optional k6 script for realistic
`/watermark` load testing.
