/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the Terraform configuration.
 * Scope        : Module (IAM/Policy)
 */

variable "iam_policy_name" {
  type        = string
  description = "The name of the IAM policy"
}

variable "iam_policy_description" {
  type        = string
  description = "The description of the IAM policy"
}

variable "iam_policy_document" {
  type        = any
  description = "The policy statement of the IAM policy"
}

variable "iam_policy_attachment_role_name" {
  type        = string
  description = "The name of the IAM role to attach the policy to"
}
