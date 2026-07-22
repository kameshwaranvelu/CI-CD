# =============================================================================
# GitHub Actions OIDC — keyless CI auth (replaces the static-key IAM user).
#
# GitHub's OIDC "sub" claim uses IMMUTABLE numeric IDs appended to the org and
# repo names, e.g.  repo:kameshwaranvelu@102864947/watermark-app@1306304347:...
# so the trust condition wildcards those "@<id>" segments.
# =============================================================================

variable "github_owner" {
  description = "GitHub org/user that owns the repos (name only, no numeric id). Set via TF_VAR_github_owner / GitHub variable."
  type        = string
  default     = ""
}

# Mono-repo: infra/ and application/ live in ONE repo, so both CI roles
# trust the same repository. Set repo_name to your mono-repo's name.
variable "repo_name" {
  description = "Name of the mono-repo (contains both infra/ and application/)."
  type        = string
  default     = ""
}

# ---- OIDC provider -----------------------------------------------------------
# Create once per account. If you already created it by hand while testing,
# import it:  terraform import aws_iam_openid_connect_provider.github \
#   arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # AWS validates GitHub's OIDC via the CA chain; the thumbprint is required
  # by the API but no longer security-critical for this provider.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---- Trust policy helper -----------------------------------------------------
# Wildcards the "@<numeric-id>" that GitHub injects into org and repo names.
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

# ---- Terraform (infra) role: broad admin to manage the stack ----------------
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

# Terraform needs broad permissions to build the whole stack. Scope this down
# to specific services later; PowerUser + IAM is a pragmatic starting point.
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

# ---- Outputs: the role ARNs to put in GitHub as variables -------------------
output "app_ci_role_arn" {
  description = "Set as APP_CI_ROLE_ARN variable in the watermark-app repo."
  value       = aws_iam_role.app_ci.arn
}

output "infra_ci_role_arn" {
  description = "Set as INFRA_CI_ROLE_ARN variable in the infra repo."
  value       = aws_iam_role.infra_ci.arn
}
