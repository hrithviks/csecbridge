/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the load balancer module.
 * Scope        : Module (Load balancer)
 */

# NLB Resource
variable "nlb_name" {
  description = "The name of the load balancer"
  type        = string
}

variable "nlb_internal_enabled" {
  description = "Whether the load balancer is internal or not"
  type        = bool
  default     = false
}

variable "nlb_subnet_ids" {
  description = "The subnet IDs for the load balancer"
  type        = list(string)
}

variable "nlb_cross_zone_enabled" {
  description = "Whether cross-zone load balancing is enabled"
  type        = bool
  default     = true
}

# NLB Target Group Resource
variable "nlb_target_group_name" {
  description = "The target group name for NLB"
  type        = string
}

variable "nlb_target_port" {
  description = "The target port for NLB"
  type        = number
}

variable "nlb_target_protocol" {
  description = "The target protocol for NLB"
  type        = string
}

variable "nlb_target_vpc_id" {
  description = "The VPC ID for the target group"
  type        = string
}

# NLB Target Group Resource Health Check
variable "nlb_target_health_check_protocol" {
  description = "The target health check protocol"
  type        = string
}

variable "nlb_target_health_check_port" {
  description = "The target health check port"
  type        = number
}

variable "nlb_target_health_check_interval" {
  description = "The target health check interval"
  type        = number
}

# NLB Listener Resource
variable "nlb_listener_port" {
  description = "The NLB listener port"
  type        = number
}

variable "nlb_listener_protocol" {
  description = "The protocol for NLB listener"
  type        = string
}
