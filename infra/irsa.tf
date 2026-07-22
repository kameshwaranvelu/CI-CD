# ---------- AWS Load Balancer Controller ----------
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.project_name}-${var.environment}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# ---------- watermark-app pod: read-only access to the assets bucket ----------
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "watermark_app_s3_read" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.watermark_assets.arn}/*"]
  }
  # Store watermarked results back into the bucket (outputs/ prefix).
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.watermark_assets.arn}/outputs/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.watermark_assets.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.watermark_assets.arn]
  }
}

module "watermark_app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.project_name}-${var.environment}-app"

  role_policy_arns = {
    s3_read = aws_iam_policy.watermark_app_s3_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["watermark:watermark-app"]
    }
  }
}

resource "aws_iam_policy" "watermark_app_s3_read" {
  name   = "${var.project_name}-${var.environment}-s3-read"
  policy = data.aws_iam_policy_document.watermark_app_s3_read.json
}
