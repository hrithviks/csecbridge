/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Defines the security group.
 * Scope        : Module (Security)
 */

resource "aws_security_group" "main" {
  name        = var.sg_name
  description = var.sg_description
  vpc_id      = var.sg_vpc_id
  tags        = var.sg_tags
}
