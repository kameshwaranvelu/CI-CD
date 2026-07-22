# Tells kube-prometheus-stack's Prometheus to scrape the app's /metrics
resource "kubectl_manifest" "watermark_app_servicemonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: watermark-app
      namespace: monitoring
      labels:
        release: kube-prometheus-stack
    spec:
      selector:
        matchLabels:
          app: watermark-app
      namespaceSelector:
        matchNames:
          - watermark
      endpoints:
        - port: http
          path: /metrics
          interval: 15s
  YAML

  depends_on = [helm_release.kube_prometheus_stack]
}

# Alert thresholds — deliberately tuned low so a short stress test trips
# them quickly rather than needing sustained load for 15+ minutes.
resource "kubectl_manifest" "watermark_app_alerts" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: watermark-app-alerts
      namespace: monitoring
      labels:
        release: kube-prometheus-stack
    spec:
      groups:
        - name: watermark-app.rules
          rules:
            - alert: WatermarkAppHighCPU
              expr: |
                sum(rate(container_cpu_usage_seconds_total{namespace="watermark",container="watermark-app"}[2m])) by (pod)
                /
                sum(kube_pod_container_resource_limits{namespace="watermark",container="watermark-app",resource="cpu"}) by (pod)
                > 0.8
              for: 1m
              labels:
                severity: warning
              annotations:
                summary: "watermark-app pod {{ $labels.pod }} CPU > 80% of limit"

            - alert: WatermarkAppHighMemory
              expr: |
                sum(container_memory_working_set_bytes{namespace="watermark",container="watermark-app"}) by (pod)
                /
                sum(kube_pod_container_resource_limits{namespace="watermark",container="watermark-app",resource="memory"}) by (pod)
                > 0.8
              for: 1m
              labels:
                severity: warning
              annotations:
                summary: "watermark-app pod {{ $labels.pod }} memory > 80% of limit"

            - alert: WatermarkAppCrashLooping
              expr: |
                increase(kube_pod_container_status_restarts_total{namespace="watermark",container="watermark-app"}[10m]) > 2
              labels:
                severity: critical
              annotations:
                summary: "watermark-app pod {{ $labels.pod }} is restarting repeatedly"

            - alert: WatermarkAppHighErrorRate
              expr: |
                sum(rate(flask_http_request_total{namespace="watermark",status=~"5.."}[2m]))
                /
                sum(rate(flask_http_request_total{namespace="watermark"}[2m]))
                > 0.1
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "watermark-app 5xx error rate > 10%"

            - alert: WatermarkAppHighLatency
              expr: |
                histogram_quantile(0.95,
                  sum(rate(flask_http_request_duration_seconds_bucket{namespace="watermark"}[2m])) by (le)
                ) > 2
              for: 1m
              labels:
                severity: warning
              annotations:
                summary: "watermark-app p95 latency > 2s"

            - alert: WatermarkAppPodDown
              expr: |
                kube_deployment_status_replicas_available{namespace="watermark",deployment="watermark-app"} == 0
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "watermark-app has zero available replicas"
  YAML

  depends_on = [helm_release.kube_prometheus_stack]
}
