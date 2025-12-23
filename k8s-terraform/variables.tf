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

  validation {
    condition     = var.main_aws_region == "ap-southeast-1"
    error_message = "The AWS region must be 'ap-southeast-1'."
  }
}

variable "main_default_tags" {
  description = "The default tags for all the resources"
  type        = map(any)
}

variable "main_cluster_name" {
  description = "The name of the Kubernetes cluster"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.main_cluster_name)
    error_message = "Cluster name must be one of: dev, qa, prod."
  }
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

  validation {
    condition     = can(cidrhost(var.network_vpc_cidr, 0))
    error_message = "The VPC CIDR block must be a valid IPv4 CIDR."
  }
}

variable "network_public_subnets_cidr" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.network_public_subnets_cidr : can(cidrhost(cidr, 0))])
    error_message = "All public subnet CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "network_private_subnets_cidr" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.network_private_subnets_cidr : can(cidrhost(cidr, 0))])
    error_message = "All private subnet CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "network_availability_zones" {
  description = "List of availability zones to distribute subnets across"
  type        = list(string)

  validation {
    condition     = alltrue([for az in var.network_availability_zones : contains(["ap-southeast-1a", "ap-southeast-1b"], az)])
    error_message = "Availability zones must be 'ap-southeast-1a' or 'ap-southeast-1b'."
  }
}

/*
* Compute module configuration variables
*/

variable "compute_control_plane_iam_role_policy" {
  description = "The IAM role policy for the control plane instances"
  type        = any
}

variable "compute_worker_nodes_iam_role_policy" {
  description = "The IAM role policy for the worker node instances"
  type        = any
}

variable "compute_k8s_instance_ami_id" {
  description = "The AMI ID for the K8s instances"
  type        = string

  validation {
    condition     = can(regex("^ami-[a-z0-9]+$", var.compute_k8s_instance_ami_id))
    error_message = "The AMI ID must be a valid AWS AMI ID starting with 'ami-'."
  }
}

variable "compute_k8s_instance_type" {
  description = "The EC2 instance type for the K8s instances"
  type        = string

  validation {
    condition     = contains(["t3.small", "t3.medium"], var.compute_k8s_instance_type)
    error_message = "Instance type must be t3.small, or t3.medium."
  }
}

variable "compute_k8s_instance_ssh_key_name" {
  description = "The SSH key for the K8s instances"
  type        = string
}

variable "devops_vpc_id" {
  description = "The ID of the DevOps VPC for peering."
  type        = string
}

variable "devops_vpc_cidr" {
  description = "The CIDR block of the DevOps VPC for routing."
  type        = string
}
