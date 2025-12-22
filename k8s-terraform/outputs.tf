/*
 * Script Name  : outputs.tf
 * Project Name : cSecBridge
 * Description  : Exposes key infrastructure attributes (e.g., Load Balancer DNS) for external consumption.
 * Scope        : Root
 */

output "control_plane_nlb_dns_name" {
  description = "The DNS name of the Control Plane Network Load Balancer."
  value       = module.control_plane_lb.nlb_dns_name
}

output "control_plane_asg_name" {
  description = "The name of the Control Plane Auto Scaling Group."
  value       = module.k8s_control_plane.autoscaling_group_id
}
