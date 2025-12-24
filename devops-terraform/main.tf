/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Provisions the DevOps infrastructure including VPC, IAM, and 
 *                EC2 instance for the self-hosted GitHub Actions runner.
 * Scope        : Root
 */

# Get the current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  RESOURCE_PREFIX = "${var.main_project_prefix}-devops"
  ENVIRONMENTS    = toset(["dev", "qa", "prod"])
  ACCOUNT_ID      = data.aws_caller_identity.current.account_id
  REGION          = data.aws_region.current.id
  PROJECT_PREFIX  = var.main_project_prefix

  # Resource Names
  VPC_NAME           = "${local.RESOURCE_PREFIX}-vpc"
  PUBLIC_SUBNET_NAME = "${local.RESOURCE_PREFIX}-public-subnet"
  IGW_NAME           = "${local.RESOURCE_PREFIX}-igw"
  PUBLIC_RT_NAME     = "${local.RESOURCE_PREFIX}-public-rt"
  SG_NAME            = "${local.RESOURCE_PREFIX}-sg"
  RUNNER_NAME        = "${local.RESOURCE_PREFIX}-runner"
  ROLE_NAME_PREFIX   = "${local.RESOURCE_PREFIX}-role"
  POLICY_NAME_PREFIX = "${local.RESOURCE_PREFIX}-policy"

  # Resource Descriptions
  SG_DESC = "Security group for DevOps runner instances"

  # Runner User Data
  GITHUB_AGENT_VERSION = "2.330.0"
  RUNNER_USER_DATA     = "devops-agent-user-data.sh"

  # IAM
  DEVOPS_POLICY_TEMPLATE = "devops-role-policy.json"
}

/*
* -----------------
* NETWORK RESOURCES
* -----------------
* Provisions the Virtual Private Cloud (VPC), subnets, and networking gateways
* for the DevOps infrastructure.
*/
resource "aws_vpc" "devops_vpc" {
  cidr_block           = var.devops_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.VPC_NAME
  }
}

resource "aws_subnet" "devops_public_subnet" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = var.devops_public_subnet_cidr
  availability_zone       = var.devops_availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = local.PUBLIC_SUBNET_NAME
  }
}

resource "aws_internet_gateway" "devops_igw" {
  vpc_id = aws_vpc.devops_vpc.id

  tags = {
    Name = local.IGW_NAME
  }
}

resource "aws_route_table" "devops_public_rt" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops_igw.id
  }

  tags = {
    Name = local.PUBLIC_RT_NAME
  }
}

resource "aws_route_table_association" "devops_public_rta" {
  subnet_id      = aws_subnet.devops_public_subnet.id
  route_table_id = aws_route_table.devops_public_rt.id
}

/*
* ---------------------------------
* SECURITY GROUP FOR DEVOPS RUNNER
* ---------------------------------
* Defines the network security boundary for the GitHub Actions runner.
* Allows outbound access for package installation and GitHub communication,
* and inbound SSH for management.
*/
resource "aws_security_group" "devops_sg" {
  name        = local.SG_NAME
  description = local.SG_DESC
  vpc_id      = aws_vpc.devops_vpc.id

  # Allow outbound access for GitHub Actions runner
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH acccess to the k8s cluster
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.devops_admin_cidr]
  }
}

# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprints (Standard list)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

/*
* --------------------------------
* EC2 INSTANCE FOR GITHUB RUNNER
* --------------------------------
* Provisions the EC2 instance that serves as the self-hosted GitHub Actions runner.
* Bootstraps Docker and Git via user data.
*/
resource "aws_instance" "devops_runner" {
  ami                         = var.devops_runner_ami_id
  instance_type               = var.devops_runner_instance_type
  subnet_id                   = aws_subnet.devops_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.devops_sg.id]
  key_name                    = var.devops_runner_key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # Security Hardening: Enforce IMDSv2 to prevent credential theft via SSRF
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data_replace_on_change = true

  # Inject user data from the template file
  user_data = templatefile(local.RUNNER_USER_DATA, {
    github_agent_version = local.GITHUB_AGENT_VERSION
    github_repository    = var.github_repository
    github_runner_token  = var.github_runner_token
    runner_name          = local.RUNNER_NAME
  })

  tags = {
    Name = local.RUNNER_NAME
  }
}

/*
* ------------------------------------
* IAM ROLES FOR ENVIRONMENT DEPLOYMENT
* ------------------------------------
* Creates distinct IAM roles for each environment (dev, qa, prod).
* These roles are assumed by the runner to perform deployments, ensuring
* isolation and least privilege based on resource tagging.
*/
resource "aws_iam_role" "environment_roles" {
  for_each = local.ENVIRONMENTS

  name = "${local.ROLE_NAME_PREFIX}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${each.key}"
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Environment = each.key
  }
}

resource "aws_iam_role_policy" "environment_policies" {
  for_each = local.ENVIRONMENTS

  name = "${local.POLICY_NAME_PREFIX}-${each.key}"
  role = aws_iam_role.environment_roles[each.key].id

  policy = templatefile(local.DEVOPS_POLICY_TEMPLATE, {
    region         = local.REGION
    account_id     = local.ACCOUNT_ID
    environment    = each.key
    backend_bucket = "csec-app-infra-backend"
    access_bucket  = "csec-app-access-logs"
    configbucket   = "csec-${each.key}-k8s-config"
    project_prefix = local.PROJECT_PREFIX
  })
}
