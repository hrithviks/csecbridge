/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Provisions EC2 compute resources via Launch Templates and Auto Scaling Groups.
 *                Enforces security best practices including IMDSv2, encrypted storage, and tagging.
 * Scope        : Module (Compute)
 */

/*
 * ---------------
 * Launch Template
 * ---------------
 * Defines the configuration for EC2 instances (AMI, type, security, user data).
 */
resource "aws_launch_template" "main" {
  name_prefix   = var.ec2_name_prefix
  image_id      = var.ec2_ami_id
  instance_type = var.ec2_instance_type
  key_name      = var.ec2_key_name

  iam_instance_profile {
    name = var.ec2_iam_instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = var.ec2_associate_public_ip_address
    security_groups             = var.ec2_security_group_ids
  }

  # Security Architecture: Enforce IMDSv2 (Instance Metadata Service Version 2).
  # This mitigates SSRF vulnerabilities by requiring session-oriented requests for metadata access.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Storage Architecture: Root volume configuration.
  # Ensures sufficient capacity (resized from default) and encryption for Kubernetes node operations.
  block_device_mappings {
    device_name = "/dev/xvda" # Default root device for Amazon Linux 2023
    ebs {
      volume_size           = var.ec2_root_volume_size
      volume_type           = var.ec2_root_volume_type
      delete_on_termination = true
      encrypted             = true
    }
  }

  # Compute Architecture: CPU Credit specification.
  # Configured for T3 (Burstable) instances to manage performance characteristics and cost.
  credit_specification {
    cpu_credits = "standard"
  }

  # User data must be base64 encoded for Launch Templates.
  user_data = var.ec2_user_data != null ? base64encode(var.ec2_user_data) : null

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { "Name" = "${var.ec2_name_prefix}" },
      var.ec2_tags
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

/*
 * ------------------
 * Auto Scaling Group
 * ------------------
 * Manages the lifecycle of EC2 instances, including scaling policies, health checks, and fleet updates.
 */
resource "aws_autoscaling_group" "main" {
  name                = "${var.ec2_name_prefix}-asg"
  vpc_zone_identifier = var.ec2_subnet_ids
  max_size            = var.ec2_asg_max_size
  min_size            = var.ec2_asg_min_size
  desired_capacity    = var.ec2_asg_desired_capacity
  target_group_arns   = var.ec2_target_group_arns

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }

  tag {
    key                 = "Name"
    value               = var.ec2_name_prefix
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.ec2_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Operational Logic: Instance Refresh Strategy.
  # Triggers a rolling update of instances when the Launch Template version changes (e.g., AMI updates).
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
