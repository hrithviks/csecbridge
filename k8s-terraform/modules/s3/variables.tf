/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the S3 module, including bucket naming and tagging.
 * Scope        : Module (S3)
 */

variable "s3_bucket_name" {
  description = "Name of the S3 bucket."
  type        = string
}

variable "s3_tags" {
  description = "Tags for the S3 bucket."
  type        = map(string)
  default     = {}
}

variable "s3_kms_key_arn" {
  description = "The ARN of the KMS key to use for encryption. If null, uses SSE-S3 (AWS Managed Key)."
  type        = string
  default     = null
}
