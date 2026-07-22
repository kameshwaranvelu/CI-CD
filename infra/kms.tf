resource "aws_kms_key" "watermark_assets" {
  description             = "Encrypts the watermark-app assets S3 bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "watermark_assets" {
  name          = "alias/${var.project_name}-${var.environment}-assets"
  target_key_id = aws_kms_key.watermark_assets.key_id
}
