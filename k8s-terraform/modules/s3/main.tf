/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Provisions S3 buckets with enforced security baselines.
 *                Includes server-side encryption, public access blocking, and secure transport policies.
 * Scope        : Module (S3)
 */

resource "aws_s3_bucket" "main" {
  bucket = var.s3_bucket_name
  tags   = var.s3_tags
}

# Enable Versioning to recover from accidental overwrites or deletions.
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access to the bucket to prevent data exposure.
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Enabled Server Side Encryption with CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      # If a KMS key is provided, use "aws:kms", otherwise use "AES256" (SSE-S3)
      sse_algorithm     = var.s3_kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.s3_kms_key_arn
    }
  }
}

# Bucket Policy to enforce SSL (HTTPS) requests only.
resource "aws_s3_bucket_policy" "secure_transport" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ForceSSLOnlyAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}
