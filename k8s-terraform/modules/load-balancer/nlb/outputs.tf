/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Defines outputs for the load balancer module.
 * Scope        : Module (Load Balancer)
 */

output "nlb_arn" {
  value       = aws_lb.main.arn
  description = "The ARN of the load balancer"
}

output "nlb_dns_name" {
  value = aws_lb.main.dns_name
}

output "nlb_target_group_arn" {
  value       = aws_lb_target_group.main.arn
  description = "The ARN of the target group"
}

output "nlb_listener_arn" {
  value       = aws_lb_listener.main.arn
  description = "The ARN of the listener"
}

output "nlb_target_group_id" {
  value       = aws_lb_target_group.main.id
  description = "The ID of the target group"
}
