/*
 * Script Name  : variables.tf
 * Project Name : cSecBridge
 * Description  : Defines input variables for the security module.
 * Scope        : Module (Security)
 */

variable "sg_name" {
  description = "The name of the security group."
  type        = string
}

variable "sg_description" {
  description = "The description of the security group."
  type        = string
}

variable "sg_tags" {
  description = "The tags required for the security group."
  type        = map(any)
}

variable "sg_vpc_id" {
  description = "The VPC ID where security groups will be created"
  type        = string
}
