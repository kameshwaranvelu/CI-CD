# ---------- CloudWatch Log Group ----------
resource "aws_cloudwatch_log_group" "watermark_app" {
  name              = "/eks/${var.project_name}-${var.environment}/watermark-app"
  retention_in_days = 14
}

# ---------- IRSA: Fluent Bit -> CloudWatch Logs ----------
# tfsec:ignore:aws-iam-no-policy-wildcards -- scoped to this one log group;
# the trailing ":*" covers its log streams, not a cross-resource wildcard
data "aws_iam_policy_document" "fluent_bit_cloudwatch" {
  # Group-level actions: DescribeLogGroups and CreateLogGroup don't operate
  # on a single fixed log-group ARN, so they need a broader resource scope
  # (all log groups in this account/region). Scoping these to one ARN is
  # what caused the AccessDenied on CreateLogStream.
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }

  # Stream/event actions scoped tightly to this one log group and its streams.
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:PutRetentionPolicy",
    ]
    resources = [
      aws_cloudwatch_log_group.watermark_app.arn,
      "${aws_cloudwatch_log_group.watermark_app.arn}:*",
    ]
  }
}

resource "aws_iam_policy" "fluent_bit_cloudwatch" {
  name   = "${var.project_name}-${var.environment}-fluent-bit-cloudwatch"
  policy = data.aws_iam_policy_document.fluent_bit_cloudwatch.json
}

module "fluent_bit_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.project_name}-${var.environment}-fluent-bit"

  role_policy_arns = {
    cloudwatch = aws_iam_policy.fluent_bit_cloudwatch.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:aws-for-fluent-bit"]
    }
  }
}

resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
  }
  depends_on = [module.eks]
}

resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.fluent_bit_irsa.iam_role_arn
    }
  }
}

# ---------- Fluent Bit DaemonSet: tails every pod's stdout/stderr -> CloudWatch ----------
resource "helm_release" "fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = "0.1.34"
  namespace  = kubernetes_namespace.amazon_cloudwatch.metadata[0].name

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.fluent_bit.metadata[0].name
  }
  # Send every pod's logs to one log group, one stream per pod — simplest
  # setup to start; split by namespace/app later if log volume grows.
  set {
    name  = "cloudWatch.region"
    value = var.aws_region
  }
  set {
    name  = "cloudWatch.logGroupName"
    value = aws_cloudwatch_log_group.watermark_app.name
  }
  set {
    name  = "cloudWatch.logStreamPrefix"
    value = "pod-"
  }
  set {
    name  = "cloudWatch.logRetentionDays"
    value = "14"
  }

  depends_on = [kubernetes_service_account.fluent_bit]
}
