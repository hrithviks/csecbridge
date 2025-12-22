/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the AWS Systems Manager Parameter Store (SSM)
 * Scope        : Module (Systems Manager)
 */

variable "ssm_parameter_name" {
  description = "The name of the SSM parameter"
  type        = string
}

variable "ssm_parameter_description" {
  description = "The description of the SSM parameter"
  type        = string
}

variable "ssm_parameter_type" {
  description = "The type of the SSM parameter"
  type        = string
}

variable "ssm_parameter_value" {
  description = "The value of the SSM parameter"
  type        = string
}
