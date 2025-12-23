/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Provisions the DevOps infrastructure including VPC, IAM, and 
 *                EC2 instance for the self-hosted GitHub Actions runner.
 * Scope        : Root
 */

locals {
  RESOURCE_PREFIX = "${var.main_project_prefix}-devops"
  ENVIRONMENTS    = toset(["dev", "qa", "prod"])

  # Resource Names
  VPC_NAME           = "${local.RESOURCE_PREFIX}-vpc"
  PUBLIC_SUBNET_NAME = "${local.RESOURCE_PREFIX}-public-subnet"
  IGW_NAME           = "${local.RESOURCE_PREFIX}-igw"
  PUBLIC_RT_NAME     = "${local.RESOURCE_PREFIX}-public-rt"
  SG_NAME            = "${local.RESOURCE_PREFIX}-sg"
  RUNNER_NAME        = "${local.RESOURCE_PREFIX}-runner"
  ROLE_NAME_PREFIX   = "${local.RESOURCE_PREFIX}-role"
  POLICY_NAME_PREFIX = "${local.RESOURCE_PREFIX}-policy"
  BASE_ROLE_NAME     = "${local.RESOURCE_PREFIX}-runner-base-role"
  BASE_PROFILE_NAME  = "${local.RESOURCE_PREFIX}-runner-base-profile"
  BASE_POLICY_NAME   = "${local.RESOURCE_PREFIX}-runner-base-policy"

  # Resource Descriptions
  SG_DESC        = "Security group for DevOps runner instances"
  BASE_ROLE_DESC = "IAM Role for the GitHub Runner EC2 instance allowing it to assume environment roles"
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

  # Allow SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.devops_admin_cidr]
  }
}

/*
* ------------------------------------
* IAM ROLE FOR RUNNER INSTANCE (BASE)
* ------------------------------------
* The base identity attached to the EC2 runner. It has no permissions itself
* other than the ability to assume the specific environment roles.
*/
resource "aws_iam_role" "runner_base_role" {
  name        = local.BASE_ROLE_NAME
  description = local.BASE_ROLE_DESC

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = local.BASE_ROLE_NAME
  }
}

resource "aws_iam_instance_profile" "runner_base_profile" {
  name = local.BASE_PROFILE_NAME
  role = aws_iam_role.runner_base_role.name
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
  iam_instance_profile        = aws_iam_instance_profile.runner_base_profile.name
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

  # Install Docker and Git as prerequisites for the runner
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io git
              systemctl enable docker
              systemctl start docker
              usermod -a -G docker ubuntu
              chmod 666 /var/run/docker.sock
              EOF

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

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/environment" = each.key
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/environment" = "true"
          }
        }
      }
    ]
  })
}
