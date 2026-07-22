resource "aws_s3_bucket" "watermark_assets" {
  bucket = "${var.project_name}-${var.environment}-assets-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "watermark_assets" {
  bucket                  = aws_s3_bucket.watermark_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "watermark_assets" {
  bucket = aws_s3_bucket.watermark_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "watermark_assets" {
  bucket = aws_s3_bucket.watermark_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.watermark_assets.arn
    }
    bucket_key_enabled = true
  }
}

# Seeds a default logo so the init container has something to fetch on
# first deploy — no manual `aws s3 cp` needed. Swap assets/watermark.png
# for your real logo and re-apply whenever you want to change it.
resource "aws_s3_object" "default_watermark_logo" {
  bucket = aws_s3_bucket.watermark_assets.id
  key    = "watermark/logo.png"
  source = "${path.module}/assets/watermark.png"
  etag   = filemd5("${path.module}/assets/watermark.png")
}

data "aws_caller_identity" "current" {}
