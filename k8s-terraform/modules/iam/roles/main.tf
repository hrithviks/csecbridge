/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Provisions IAM Roles with defined trust policies.
 * Scope        : Module (IAM Role)
 */

resource "aws_iam_role" "main" {
  name               = var.iam_role_name
  description        = var.iam_role_description
  assume_role_policy = jsonencode(var.iam_role_assume_role_policy)
  tags               = var.iam_role_tags
}
