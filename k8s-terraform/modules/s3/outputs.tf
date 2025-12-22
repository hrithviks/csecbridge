/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Exposes S3 bucket attributes (ID, ARN) for reference by other modules.
 * Scope        : Module (S3)
 */

output "s3_bucket_id" {
  description = "The name of the bucket."
  value       = aws_s3_bucket.main.id
}

output "s3_bucket_arn" {
  description = "The ARN of the bucket."
  value       = aws_s3_bucket.main.arn
}
