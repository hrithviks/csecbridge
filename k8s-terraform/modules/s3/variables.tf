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
