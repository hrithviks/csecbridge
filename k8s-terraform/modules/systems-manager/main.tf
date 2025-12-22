/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Defines the AWS Systems Manager Parameter Store (SSM)
 * Scope        : Module (Systems Manager)
 */

resource "aws_ssm_parameter" "main" {
  name        = var.ssm_parameter_name
  description = var.ssm_parameter_description
  type        = var.ssm_parameter_type
  value       = var.ssm_parameter_value

  lifecycle {
    ignore_changes = [value]
  }
}
