/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the IAM Role module, including trust policies and tags.
 * Scope        : Module (IAM Role)
 */

variable "iam_role_name" {
  description = "The name of the IAM role."
  type        = string
}

variable "iam_role_assume_role_policy" {
  description = "The policy that grants an entity permission to assume the role."
  type        = any
}

variable "iam_role_description" {
  description = "The description of the IAM role."
  type        = string
  default     = null
}

variable "iam_role_tags" {
  description = "A map of tags to assign to the role."
  type        = map(string)
  default     = {}
}
