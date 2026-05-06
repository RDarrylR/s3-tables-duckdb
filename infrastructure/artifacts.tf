# S3 bucket for deployment artifacts. The Lambda layer zip exceeds Lambda's
# direct-upload limit (~67 MB base64), so it's uploaded to this bucket and the
# layer resource references it via s3_bucket / s3_key.

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}-artifacts-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_object" "ingester_layer" {
  bucket      = aws_s3_bucket.artifacts.id
  key         = "ingester-deps-${filebase64sha256("${path.module}/../ingester/dist/ingester-deps.zip")}.zip"
  source      = "${path.module}/../ingester/dist/ingester-deps.zip"
  source_hash = filebase64sha256("${path.module}/../ingester/dist/ingester-deps.zip")
}
