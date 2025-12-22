/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the Compute module, including instance specifications and scaling parameters.
 * Scope        : Module (Compute)
 */

# Basic variables
variable "ec2_name_prefix" {
  description = "Prefix to be added to resource names."
  type        = string
}

# EC2 variables
variable "ec2_ami_id" {
  description = "The AMI ID to use for the instances."
  type        = string
}

variable "ec2_instance_type" {
  description = "The EC2 instance type."
  type        = string
}

variable "ec2_key_name" {
  description = "The key pair name for SSH access."
  type        = string
  default     = null
}

variable "ec2_subnet_ids" {
  description = "List of subnet IDs to launch resources in."
  type        = list(string)
}

variable "ec2_security_group_ids" {
  description = "List of security group IDs to associate."
  type        = list(string)
  default     = []
}

variable "ec2_associate_public_ip_address" {
  description = "Whether to associate a public IP address."
  type        = bool
  default     = false
}

variable "ec2_user_data" {
  description = "User data script to run on instance launch"
  type        = string
  default     = null
}

variable "ec2_asg_max_size" {
  description = "Maximum size of the Auto Scaling Group."
  type        = number
}

variable "ec2_asg_min_size" {
  description = "Minimum size of the Auto Scaling Group."
  type        = number
}

variable "ec2_asg_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group."
  type        = number
}

variable "ec2_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "ec2_iam_instance_profile_name" {
  description = "The IAM instance profile name to associate with the instances."
  type        = string
}

variable "ec2_root_volume_size" {
  description = "Size of the root volume in GB."
  type        = number
}

variable "ec2_root_volume_type" {
  description = "Type of the root volume (e.g., gp3)."
  type        = string
}

variable "ec2_target_group_arns" {
  description = "List of Target Group ARNs to associate with the Auto Scaling Group."
  type        = list(string)
  default     = []
}
