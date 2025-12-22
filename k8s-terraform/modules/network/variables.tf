/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Input variables for the network module.
 * Scope        : Module (Network)
 */

variable "vpc_resource_prefix" {
  description = "The prefix name for resources"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "vpc_public_subnets_cidr" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "vpc_private_subnets_cidr" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
}

variable "vpc_availability_zones" {
  description = "List of availability zones to distribute subnets across"
  type        = list(string)
}
