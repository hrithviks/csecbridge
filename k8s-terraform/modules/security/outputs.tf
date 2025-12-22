/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Defines outputs for the security module.
 * Scope        : Module (Security)
 */

output "sg_id" {
  value = aws_security_group.main.id
}
