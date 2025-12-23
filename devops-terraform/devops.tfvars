# Main section variables
main_aws_region     = "ap-southeast-1"
main_project_prefix = "csec"
main_default_tags = {
  project     = "csec-bridge"
  application = "csec-devops-cluster"
  created     = "21-Dec-2025"
  contact     = "devops@csecbridge.org"
}

# DevOps Network configuration
devops_vpc_cidr           = "10.200.0.0/16"
devops_public_subnet_cidr = "10.200.1.0/24"
devops_availability_zone  = "ap-southeast-1a"

# DevOps Compute configuration
devops_runner_ami_id        = "ami-06c4be2792f419b7b" # Amazon Linux 2023 (ap-southeast-1)
devops_runner_instance_type = "t3.small"
devops_runner_key_name      = "csec-ssh-key-pair"

# Security
devops_admin_cidr = "0.0.0.0/0" # TODO: Replace with specific IP for security hardening
