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

variable "main_environment" {
  description = "The deployment environment (e.g., dev, qa, prod)"
  type        = string
}

variable "main_default_tags" {
  description = "The default tags for all the resources"
  type        = map(any)
}

variable "main_cluster_name" {
  description = "The name of the Kubernetes cluster"
  type        = string
}

variable "main_project_prefix" {
  description = "The project prefix for resources"
  type        = string
}

/*
* Network module configuration variables
*/
variable "network_vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "network_public_subnets_cidr" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "network_private_subnets_cidr" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
}

variable "network_availability_zones" {
  description = "List of availability zones to distribute subnets across"
  type        = list(string)
}

/*
* Control plane compute module configuration variables
*/
variable "compute_control_plane_iam_role_policy" {
  description = "The IAM role policy for the control plane instances"
  type        = any
}

variable "compute_control_plane_ami_id" {
  description = "The AMI ID for the control plane instances"
  type        = string
}

variable "compute_control_plane_instance_type" {
  description = "The EC2 instance type for the control plane instances"
  type        = string
}

variable "compute_control_plane_key_name" {
  description = "The SSH key to use for the control plane instance."
  type        = string
}

/*
* Worker node compute module configuration variables
*/
variable "compute_worker_nodes_iam_role_policy" {
  description = "The IAM role policy for the worker node instances"
  type        = any
}

variable "compute_worker_nodes_ami_id" {
  description = "The AMI ID for the worker node instances"
  type        = string
}

variable "compute_worker_nodes_instance_type" {
  description = "The EC2 instance type for the worker node instances"
  type        = string
}

variable "compute_worker_nodes_key_name" {
  description = "The SSH key to use for the worker node instance."
  type        = string
}
