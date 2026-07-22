resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "watermark" {
  metadata {
    name = "watermark"
  }
  depends_on = [module.eks]
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
  }
  depends_on = [module.eks]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_lb_controller_chart_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [kubernetes_service_account.alb_controller]
}

# ---------- ArgoCD ----------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Internal-only URL via a private ALB: reachable from inside the VPC
  # (VPN / bastion / another in-VPC workload) using its own free AWS DNS
  # name, but never exposed to the public internet. server.insecure lets
  # argocd-server speak plain HTTP so the ALB doesn't need a cert.
  values = [<<-YAML
    server:
      service:
        type: ClusterIP
      extraArgs:
        - --insecure
      ingress:
        enabled: true
        ingressClassName: alb
        annotations:
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
          alb.ingress.kubernetes.io/backend-protocol: HTTP
  YAML
  ]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Bootstraps the app-of-apps: once this Application exists, ArgoCD takes
# over managing everything under the GitOps repo, including itself if you
# choose to manage this Helm release via GitOps later.
# ArgoCD repository credential — lets ArgoCD read the (private) app repo.
# Managed as code so it survives cluster rebuilds; no manual kubectl needed.
resource "kubernetes_secret" "argocd_app_repo" {
  count = var.app_repo_url != "" && var.gitops_pat != "" ? 1 : 0

  metadata {
    name      = "watermark-app-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.app_repo_url
    username = var.app_repo_username
    password = var.gitops_pat
  }

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "watermark_app_argocd_application" {
  count     = var.app_repo_url != "" ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: watermark-app
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: ${var.app_repo_url}
        targetRevision: main
        path: application/deploy
      destination:
        server: https://kubernetes.default.svc
        namespace: watermark
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML

  depends_on = [helm_release.argocd, kubernetes_secret.argocd_app_repo]
}

# ---------- Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager) ----------
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Internal-only URL via a private ALB, same pattern as ArgoCD above —
  # reachable inside the VPC, never on the public internet.
  values = [<<-YAML
    grafana:
      service:
        type: ClusterIP
      adminPassword: "${local.grafana_admin_password_effective}"
      resources:
        requests:
          cpu: 50m
          memory: 100Mi
        limits:
          memory: 200Mi
      ingress:
        enabled: true
        ingressClassName: alb
        annotations:
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
        path: /
        pathType: Prefix
    alertmanager:
      alertmanagerSpec:
        resources:
          requests:
            cpu: 25m
            memory: 50Mi
          limits:
            memory: 100Mi
      ingress:
        enabled: true
        ingressClassName: alb
        annotations:
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
        paths:
          - /
        pathType: Prefix
    prometheus:
      prometheusSpec:
        # Trimmed for tiny t3.micro nodes: short retention + capped memory
        # so Prometheus actually schedules instead of sitting Pending.
        retention: 6h
        resources:
          requests:
            cpu: 100m
            memory: 300Mi
          limits:
            memory: 500Mi
    prometheusOperator:
      resources:
        requests:
          cpu: 50m
          memory: 100Mi
        limits:
          memory: 200Mi
    # kube-state-metrics + node-exporter are light but set requests so the
    # scheduler places them predictably on constrained nodes.
    kube-state-metrics:
      resources:
        requests:
          cpu: 25m
          memory: 64Mi
    nodeExporter:
      resources:
        requests:
          cpu: 25m
          memory: 32Mi
  YAML
  ]

  depends_on = [helm_release.aws_load_balancer_controller]
}
