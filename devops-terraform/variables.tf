/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the Terraform configuration.
 * Scope        : Root
 */

/*
* Main configuration variables
*/
variable "main_aws_region" {
  description = "The AWS region to deploy the cluster into"
  type        = string
}

variable "main_default_tags" {
  description = "The default tags for all the resources"
  type        = map(any)
}

variable "main_project_prefix" {
  description = "The project prefix for resources"
  type        = string
}

/*
* DevOps Network configuration variables
*/
variable "devops_vpc_cidr" {
  description = "The CIDR block for the DevOps VPC"
  type        = string
}

variable "devops_public_subnet_cidr" {
  description = "The CIDR block for the DevOps public subnet"
  type        = string
}

variable "devops_availability_zone" {
  description = "The availability zone for the DevOps subnet"
  type        = string
}

/*
* DevOps Compute configuration variables
*/
variable "devops_runner_ami_id" {
  description = "The AMI ID for the GitHub Actions runner instance"
  type        = string
}

variable "devops_runner_instance_type" {
  description = "The EC2 instance type for the GitHub Actions runner"
  type        = string
}

variable "devops_runner_key_name" {
  description = "The SSH key name for the runner instance"
  type        = string
  default     = null
}

variable "devops_admin_cidr" {
  description = "The CIDR block allowed to SSH into the runner (e.g., your public IP)"
  type        = string
}

variable "github_repository" {
  description = "The GitHub repository (org/repo) allowed to assume roles via OIDC"
  type        = string
}
