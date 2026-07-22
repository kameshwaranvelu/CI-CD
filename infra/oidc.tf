variable "github_owner" {
  description = "GitHub org/user that owns the repos (name only, no numeric id). Set via TF_VAR_github_owner / GitHub variable."
  type        = string
  default     = ""
}

variable "repo_name" {
  description = "Name of the mono-repo (contains both infra/ and application/)."
  type        = string
  default     = ""
}

# ---- OIDC provider -----------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's OIDC via the CA chain; the thumbprint is required
  # by the API but no longer security-critical for this provider.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  app_repo_sub   = "repo:${var.github_owner}*/${var.repo_name}*:*"
  infra_repo_sub = "repo:${var.github_owner}*/${var.repo_name}*:*"
}

# ---- App CI role: push images to ECR ----------------------------------------
data "aws_iam_policy_document" "app_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.app_repo_sub]
    }
  }
}

resource "aws_iam_role" "app_ci" {
  name               = "${var.project_name}-${var.environment}-app-ci"
  assume_role_policy = data.aws_iam_policy_document.app_ci_trust.json
}

# Reuse the same ECR push permissions the old user had.
data "aws_iam_policy_document" "app_ci_ecr" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
    ]
    resources = [aws_ecr_repository.watermark_app.arn]
  }
}

resource "aws_iam_role_policy" "app_ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.app_ci.id
  policy = data.aws_iam_policy_document.app_ci_ecr.json
}

data "aws_iam_policy_document" "infra_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.infra_repo_sub]
    }
  }
}

resource "aws_iam_role" "infra_ci" {
  name               = "${var.project_name}-${var.environment}-infra-ci"
  assume_role_policy = data.aws_iam_policy_document.infra_ci_trust.json
}

# tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy_attachment" "infra_ci_power" {
  role       = aws_iam_role.infra_ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM management (roles, policies, OIDC) isn't in PowerUserAccess — add it.
data "aws_iam_policy_document" "infra_ci_iam" {
  statement {
    effect = "Allow"
    actions = [
      "iam:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "infra_ci_iam" {
  name   = "iam-management"
  role   = aws_iam_role.infra_ci.id
  policy = data.aws_iam_policy_document.infra_ci_iam.json
}

output "app_ci_role_arn" {
  description = "Set as APP_CI_ROLE_ARN variable in the watermark-app repo."
  value       = aws_iam_role.app_ci.arn
}

output "infra_ci_role_arn" {
  description = "Set as INFRA_CI_ROLE_ARN variable in the infra repo."
  value       = aws_iam_role.infra_ci.arn
}
