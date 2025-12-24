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

  # IAM allowed actions for "apply" and "destroy"
  IAM_WRITE_ACTIONS = [
    "ec2:*",
    "elasticloadbalancing:*",
    "autoscaling:*",
    "iam:*",
    "s3:*",
    "ssm:*",
    "logs:*",
    "cloudwatch:*",
    "kms:*"
  ]

  # IAM allowed actions for state refresh
  IAM_READ_ACTIONS = [
    "ec2:Describe*",
    "iam:List*",
    "iam:Get*",
    "s3:List*",
    "s3:Get*",
    "autoscaling:Describe*",
    "elasticloadbalancing:Describe*",
    "ssm:Describe*",
    "ssm:GetParameter*",
    "kms:Describe*",
    "kms:List*",
    "kms:Get*"
  ]

  # IAM allowed resources for "apply" and "destroy"
  IAM_ALLOWED_RESOURCES = [
    # Region-specific resources in this account (EC2, ELB, ASG, SSM, Logs)
    "arn:aws:ec2:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:elasticloadbalancing:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:autoscaling:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:ssm:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:logs:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:cloudwatch:${local.REGION}:${local.ACCOUNT_ID}:*",
    "arn:aws:kms:${local.REGION}:${local.ACCOUNT_ID}:*",
    # Allow using public AMIs (owned by other accounts)
    "arn:aws:ec2:${local.REGION}::image/*",
    # IAM Resources (Enforce naming prefix)
    "arn:aws:iam::${local.ACCOUNT_ID}:role/${local.PROJECT_PREFIX}-*",
    "arn:aws:iam::${local.ACCOUNT_ID}:policy/${local.PROJECT_PREFIX}-*",
    "arn:aws:iam::${local.ACCOUNT_ID}:instance-profile/${local.PROJECT_PREFIX}-*",
    # S3 Buckets (Enforce naming prefix)
    "arn:aws:s3:::${local.PROJECT_PREFIX}-*",
    "arn:aws:s3:::${local.PROJECT_PREFIX}-*/*"
  ]
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

  # Install Docker and Git as prerequisites for the runner
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io git curl jq libdigest-sha-perl

              echo "Enabling Docker..."
              systemctl enable docker
              systemctl start docker
              usermod -a -G docker ubuntu
              chmod 666 /var/run/docker.sock

              echo "Registering GitHub Actions runner..."
              mkdir /home/ubuntu/actions-runner && cd /home/ubuntu/actions-runner
              LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/v//')
              [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ] && LATEST_VERSION="2.312.0"
              curl -o actions-runner-linux-x64-$${LATEST_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v$${LATEST_VERSION}/actions-runner-linux-x64-$${LATEST_VERSION}.tar.gz
              tar xzf ./actions-runner-linux-x64-$${LATEST_VERSION}.tar.gz
              ./bin/installdependencies.sh

              chown -R ubuntu:ubuntu /home/ubuntu/actions-runner
              su - ubuntu -c "cd /home/ubuntu/actions-runner && ./config.sh --url https://github.com/${var.github_repository} --token ${var.github_runner_token} --unattended --name ${local.RUNNER_NAME} --labels csec-self-hosted"
              ./svc.sh install ubuntu
              ./svc.sh start
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
      # Permission to create/destroy/update managed resources.
      {
        Effect   = "Allow"
        Action   = local.IAM_WRITE_ACTIONS
        Resource = local.IAM_ALLOWED_RESOURCES
        Condition = {
          StringEqualsIfExists = {
            "aws:ResourceTag/environment" = each.key
          }
        }
      },
      # Permission to create test S3 bucket for validation
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket"
        ]
        Resource = "arn:aws:s3:::${local.PROJECT_PREFIX}-*"
        Condition = {
          Null = {
            "aws:ResourceTag/environment" = "true"
          }
        }
      },
      # Permission to get the tfvars file for each environment.
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::csec-app-infra-backend/k8s-cluster-config/${each.key}.tfvars"
      },
      # Permission to create and update state file and lock files.
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::csec-app-infra-backend/k8s-cluster/csec-${each.key}.tfstate*"
      },
      # Explicit permission to list the bucket contents.
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::csec-app-infra-backend"
      },
      # Permission to capture the state of all managed resources.
      {
        Effect   = "Allow"
        Action   = local.IAM_READ_ACTIONS
        Resource = "*"
      }
    ]
  })
}
