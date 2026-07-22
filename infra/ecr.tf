resource "aws_ecr_repository" "watermark_app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true # ECR's own scan, in addition to Trivy in CI
  }
}

resource "aws_ecr_lifecycle_policy" "watermark_app" {
  repository = aws_ecr_repository.watermark_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
