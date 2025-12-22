/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Exposes IAM Role attributes (ARN, Name, ID).
 * Scope        : Module (IAM Role)
 */

output "iam_role_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM role."
  value       = aws_iam_role.main.arn
}

output "iam_role_name" {
  description = "The name of the IAM role."
  value       = aws_iam_role.main.name
}

output "iam_role_id" {
  description = "The stable and unique ID of the IAM role."
  value       = aws_iam_role.main.id
}
