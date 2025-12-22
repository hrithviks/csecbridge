/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Defines the load balancer resources for the module.
 * Scope        : Module (Load Balancer)
 */

resource "aws_lb" "main" {
  name                             = var.nlb_name
  internal                         = var.nlb_internal_enabled
  load_balancer_type               = "network"
  subnets                          = var.nlb_subnet_ids
  enable_cross_zone_load_balancing = var.nlb_cross_zone_enabled
}

resource "aws_lb_target_group" "main" {
  name     = var.nlb_target_group_name
  port     = var.nlb_target_port
  protocol = var.nlb_target_protocol
  vpc_id   = var.nlb_target_vpc_id

  health_check {
    protocol = var.nlb_target_health_check_protocol
    port     = var.nlb_target_health_check_port
    interval = var.nlb_target_health_check_interval
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.nlb_listener_port
  protocol          = var.nlb_listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
