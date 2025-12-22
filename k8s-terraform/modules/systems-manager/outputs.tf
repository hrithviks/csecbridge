/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Defines outputs for the AWS Systems Manager Parameter Store (SSM) module
 * Scope        : Module (Systems Manager)
 */

output "ssm_parameter_name" {
  description = "The name of the SSM parameter"
  value       = aws_ssm_parameter.main.name
}

output "ssm_parameter_arn" {
  description = "The description of the SSM parameter"
  value       = aws_ssm_parameter.main.arn
}
