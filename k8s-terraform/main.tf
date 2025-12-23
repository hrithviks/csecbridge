/*
 * Script Name  : main.tf
 * Project Name : cSecBridge
 * Description  : Orchestrates the deployment of the self-managed Kubernetes 
 *                cluster infrastructure. Integrates networking, security, 
 *                compute, and storage resources.
 * Scope        : Root
 */

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "access_logs" {
  bucket = "csec-app-access-logs"
  region = var.main_aws_region
}

locals {
  RESOURCE_PREFIX = "${var.main_project_prefix}-${var.main_cluster_name}"

  # Resource Names
  CP_SG_NAME                   = "${local.RESOURCE_PREFIX}-control-plane-sg"
  WORKER_SG_NAME               = "${local.RESOURCE_PREFIX}-worker-nodes-sg"
  IAM_ROLE_CP_NAME             = "${local.RESOURCE_PREFIX}-control-plane-role"
  IAM_PROFILE_CP_NAME          = "${local.RESOURCE_PREFIX}-control-plane-profile"
  IAM_ROLE_WN_NAME             = "${local.RESOURCE_PREFIX}-worker-nodes-role"
  IAM_PROFILE_WN_NAME          = "${local.RESOURCE_PREFIX}-worker-nodes-profile"
  IAM_ROLE_FLOW_LOG_NAME       = "${local.RESOURCE_PREFIX}-vpc-flow-log-role"
  IAM_POLICY_FLOW_LOG_NAME     = "${local.RESOURCE_PREFIX}-vpc-flow-log-policy"
  SSM_PARAM_JOIN_CMD_NAME      = "/${local.RESOURCE_PREFIX}/k8s/join-command"
  S3_KUBECONFIG_NAME           = "${local.RESOURCE_PREFIX}-k8s-config"
  IAM_POLICY_CP_SSM_WRITE_NAME = "${local.RESOURCE_PREFIX}-cp-ssm-write-policy"
  IAM_POLICY_CP_S3_WRITE_NAME  = "${local.RESOURCE_PREFIX}-cp-s3-write-policy"
  IAM_POLICY_WN_SSM_READ_NAME  = "${local.RESOURCE_PREFIX}-wn-ssm-read-policy"
  NLB_CP_NAME                  = "${local.RESOURCE_PREFIX}-control-plane-nlb"
  NLB_TG_CP_NAME               = "${local.RESOURCE_PREFIX}-control-plane-tg"
  EC2_CP_NAME_PREFIX           = "${local.RESOURCE_PREFIX}-control-plane"
  EC2_WN_NAME_PREFIX           = "${local.RESOURCE_PREFIX}-worker-node"

  # Resource Descriptions
  CP_SG_DESC                   = "Security Group for Control Plane instances"
  CP_SG_SSH_INGRESS            = "Allow SSH ingress traffic to Control Plane"
  CP_SG_API_INGRESS            = "Allow Kubernetes API ingress traffic to Control Plane"
  CP_SG_K8S_API_EGRESS         = "Allow Kubernetes API egress traffic from Control Plane to Worker Nodes"
  CP_SG_K8S_SSH_EGRESS         = "Allow SSH egress traffic from Control Plane to Worker Nodes"
  CP_SG_INTERNET_ACCESS        = "Allow unrestricted internet egress from Control Plane"
  WORKER_SG_DESC               = "Security Group for Worker Node instances"
  WORKER_SG_K8S_API_INGRESS    = "Allow Kubelet API ingress traffic from Control Plane to Worker Nodes"
  WORKER_SG_K8S_SSH_INGRESS    = "Allow SSH ingress traffic from Control Plane to Worker Nodes"
  WORKER_SG_INTERNET_ACCESS    = "Allow unrestricted internet egress from Worker Nodes"
  IAM_ROLE_CP_DESC             = "IAM Role for Control Plane instances"
  IAM_ROLE_WN_DESC             = "IAM Role for Worker Node instances"
  IAM_ROLE_FLOW_LOG_DESC       = "IAM Role for VPC Flow Logs"
  IAM_POLICY_FLOW_LOG_DESC     = "Policy granting VPC Flow Logs access to CloudWatch"
  SSM_PARAM_JOIN_CMD_DESC      = "Stores the kubeadm join command required for worker nodes to join the cluster"
  IAM_POLICY_CP_SSM_WRITE_DESC = "Policy granting Control Plane write access to SSM Parameter Store"
  IAM_POLICY_CP_S3_WRITE_DESC  = "Policy granting Control Plane write access to Kubeconfig S3 Bucket"
  IAM_POLICY_WN_SSM_READ_DESC  = "Policy granting Worker Nodes read access to SSM Parameter Store"
}

/*
* --------------------------
* IAM ROLE FOR VPC FLOW LOGS
* --------------------------
* Configures the IAM identity for VPC Flow Logs to publish logs to CloudWatch.
*/
module "iam_role_vpc_flow_log" {
  source               = "./modules/iam/roles"
  iam_role_name        = local.IAM_ROLE_FLOW_LOG_NAME
  iam_role_description = local.IAM_ROLE_FLOW_LOG_DESC
  iam_role_assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
}

/*
* ----------------------------
* IAM POLICY FOR VPC FLOW LOGS
* ----------------------------
* Grants the VPC Flow Logs role permission to write logs to CloudWatch.
*/
module "iam_policy_vpc_flow_log" {
  source = "./modules/iam/policies"

  # Policy Config
  iam_policy_name        = local.IAM_POLICY_FLOW_LOG_NAME
  iam_policy_description = local.IAM_POLICY_FLOW_LOG_DESC
  iam_policy_document = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = aws_cloudwatch_log_group.flow_log.arn
      }
    ]
  }

  # Policy Attachment Config
  iam_policy_attachment_role_name = module.iam_role_vpc_flow_log.iam_role_name
}

/*
* -----------------
* NETWORK RESOURCES
* -----------------
* Provisions the Virtual Private Cloud (VPC), subnets, and networking gateways.
* Establishes the foundational network topology with public and private 
* isolation zones required for the Kubernetes cluster.
*/

# Create log group for flow logs
resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc-flow-log/${local.RESOURCE_PREFIX}-vpc"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.s3_key.arn
}

module "network" {
  source                       = "./modules/network"
  vpc_resource_prefix          = local.RESOURCE_PREFIX
  vpc_cidr                     = var.network_vpc_cidr
  vpc_public_subnets_cidr      = var.network_public_subnets_cidr
  vpc_private_subnets_cidr     = var.network_private_subnets_cidr
  vpc_availability_zones       = var.network_availability_zones
  vpc_flow_log_iam_role_arn    = module.iam_role_vpc_flow_log.iam_role_arn
  vpc_flow_log_destination_arn = aws_cloudwatch_log_group.flow_log.arn
}

/*
* --------------------------------
* SECURITY GROUP FOR CONTROL PLANE
* --------------------------------
* Defines the network security boundary for Control Plane instances.
* Acts as the primary firewall, controlling ingress and egress traffic for the
* Kubernetes API server and internal cluster communication.
*/
module "control_plane_security" {
  source         = "./modules/security"
  sg_name        = local.CP_SG_NAME
  sg_description = local.CP_SG_DESC
  sg_vpc_id      = module.network.vpc_id
  sg_tags        = {}
}

/*
* -------------------------------
* SECURITY GROUP FOR WORKER NODES
* -------------------------------
* Defines the network security boundary for Worker Node instances.
* Manages traffic flow for application workloads, Kubelet communication, and
* inter-node networking.
*/
module "worker_node_security" {
  source         = "./modules/security"
  sg_name        = local.WORKER_SG_NAME
  sg_description = local.WORKER_SG_DESC
  sg_vpc_id      = module.network.vpc_id
  sg_tags        = {}
}

/*
* --------------------------------------
* SECURITY GROUP RULES FOR CONTROL PLANE
* --------------------------------------
* Rule 1: Ingress to control plane allowing SSH traffic.
* Rule 2: Egress from control plane to worker node on Kubelet port (10250).
* Rule 3: Egress from control plane to worker node on SSH port.
*/
resource "aws_vpc_security_group_ingress_rule" "cp_ssh_ingress" {
  security_group_id = module.control_plane_security.sg_id
  description       = local.CP_SG_SSH_INGRESS
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "cp_api_ingress" {
  security_group_id = module.control_plane_security.sg_id
  description       = local.CP_SG_API_INGRESS
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 6443
  ip_protocol       = "tcp"
  to_port           = 6443
}

resource "aws_vpc_security_group_egress_rule" "cp_to_worker_k8s" {
  security_group_id            = module.control_plane_security.sg_id
  description                  = local.CP_SG_K8S_API_EGRESS
  referenced_security_group_id = module.worker_node_security.sg_id
  from_port                    = 10250
  ip_protocol                  = "tcp"
  to_port                      = 10250
}

resource "aws_vpc_security_group_egress_rule" "cp_to_worker_ssh" {
  security_group_id            = module.control_plane_security.sg_id
  description                  = local.CP_SG_K8S_SSH_EGRESS
  referenced_security_group_id = module.worker_node_security.sg_id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

/*
* -------------------------------------
* SECURITY GROUP RULES FOR WORKER NODES
* -------------------------------------
* Rule 1: Ingress to worker node from control plane for SSH
* Rule 1: Ingress to worker node from control plane for Kubelet port (10250)
* NOTE:
* All outbound traffic from control plane is allowed (No private connections).
* Additional egress rules to be configured to allow private connections based 
* on security revamp.
*/
resource "aws_vpc_security_group_ingress_rule" "worker_from_cp_ssh" {
  security_group_id            = module.worker_node_security.sg_id
  description                  = local.WORKER_SG_K8S_SSH_INGRESS
  referenced_security_group_id = module.control_plane_security.sg_id
  from_port                    = 10250
  ip_protocol                  = "tcp"
  to_port                      = 10250
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_cp_api" {
  security_group_id            = module.worker_node_security.sg_id
  description                  = local.WORKER_SG_K8S_API_INGRESS
  referenced_security_group_id = module.control_plane_security.sg_id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

/*
* ----------------------------------------
* SECURITY GROUP RULES FOR INTERNET ACCESS
* ----------------------------------------
* Essential for package installation, image pulling, and connectivity checks (ping).
* Rule 1: Allow egress from control plane to internet.
* Rule 2: Allow egress from worker nodes to internet.
*/
resource "aws_vpc_security_group_egress_rule" "cp_internet_access" {
  security_group_id = module.control_plane_security.sg_id
  description       = local.CP_SG_INTERNET_ACCESS
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "worker_internet_access" {
  security_group_id = module.worker_node_security.sg_id
  description       = local.WORKER_SG_INTERNET_ACCESS
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

/*
* ---------------------------------------------------------
* IAM ROLE AND INSTANCE PROFILE FOR CONTROL PLANE INSTANCES
* ---------------------------------------------------------
* Configures the IAM identity and permissions for Control Plane instances.
* Attaches necessary policies for SSM, S3, and EC2 interactions required for
* cluster bootstrapping and management.
*/
module "iam_role_control_plane" {
  source                      = "./modules/iam/roles"
  iam_role_name               = local.IAM_ROLE_CP_NAME
  iam_role_description        = local.IAM_ROLE_CP_DESC
  iam_role_assume_role_policy = var.compute_control_plane_iam_role_policy
}

resource "aws_iam_instance_profile" "iam_instance_profile_cp" {
  name = local.IAM_PROFILE_CP_NAME
  role = module.iam_role_control_plane.iam_role_name
}

/*
* ----------------------------------
* IAM ROLE FOR WORKER NODE INSTANCES
* ----------------------------------
* Configures the IAM identity and permissions for Worker Node instances.
* Grants least-privilege access required for joining the cluster, pulling images,
* and communicating with the Control Plane.
*/
module "iam_role_worker_nodes" {
  source                      = "./modules/iam/roles"
  iam_role_name               = local.IAM_ROLE_WN_NAME
  iam_role_description        = local.IAM_ROLE_WN_DESC
  iam_role_assume_role_policy = var.compute_worker_nodes_iam_role_policy
}

resource "aws_iam_instance_profile" "iam_instance_profile_wn" {
  name = local.IAM_PROFILE_WN_NAME
  role = module.iam_role_worker_nodes.iam_role_name
}

/*
* --------------------------------------
* SSM PARAMETER FOR CLUSTER JOIN COMMAND
* --------------------------------------
* Creates a SecureString parameter in AWS Systems Manager Parameter Store.
* Serves as a secure "dead drop" for the Control Plane to store the
* 'kubeadm join' command after cluster initialization.
*
* Worker nodes read this parameter during boot to automatically join the cluster.
* The 'value' attribute is ignored by Terraform to ensure the actual token
* generated by the Control Plane is not overwritten by the placeholder.
*/
module "ssm_parameter_cluster_join_command" {
  source = "./modules/systems-manager"

  # SSM Parameter Config
  ssm_parameter_name        = local.SSM_PARAM_JOIN_CMD_NAME
  ssm_parameter_description = local.SSM_PARAM_JOIN_CMD_DESC
  ssm_parameter_type        = "SecureString"
  ssm_parameter_value       = "NOT_READY"
}

/*
* -------------------------
* KMS KEY FOR S3 ENCRYPTION
* -------------------------
* Customer Managed Key (CMK) for encrypting S3 buckets
* to meet compliance requirements.
*/
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json
}

resource "aws_kms_alias" "s3_key" {
  name          = "alias/${local.RESOURCE_PREFIX}-s3-key"
  target_key_id = aws_kms_key.s3_key.key_id
}

data "aws_iam_policy_document" "kms_key_policy" {

  # Allow admin user to manage the key
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow S3 Service to encrypt data
  statement {
    sid    = "Allow S3 Service for Logging"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow CloudWatch Logs to encrypt/decrypt data
  statement {
    sid    = "Allow CloudWatch Logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.main_aws_region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.main_aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

/*
* ------------------------
* S3 BUCKET FOR KUBECONFIG
* ------------------------
* Stores the admin kubeconfig file securely using server-side encryption.
* Replaces SSM Parameter Store for this artifact due to size limitations.
*/
module "s3_kubeconfig_bucket" {
  source = "./modules/s3"

  s3_bucket_name = local.S3_KUBECONFIG_NAME
  s3_kms_key_arn = aws_kms_key.s3_key.arn
  s3_tags        = {}
}

resource "aws_s3_bucket_logging" "kubeconfig_logging" {
  bucket        = module.s3_kubeconfig_bucket.s3_bucket_id
  target_bucket = data.aws_s3_bucket.access_logs.id
  target_prefix = "kubeconfig-logs/"
}

/*
* ---------------------------------------
* IAM POLICY FOR CONTROL PLANE SSM ACCESS
* ---------------------------------------
* Grants the Control Plane permission to write the cluster join command to 
* SSM Parameter Store. Enables automated distribution of the join token to worker nodes.
*/
module "iam_policy_control_plane_ssm_write" {
  source = "./modules/iam/policies"

  # Policy Config
  iam_policy_name        = local.IAM_POLICY_CP_SSM_WRITE_NAME
  iam_policy_description = local.IAM_POLICY_CP_SSM_WRITE_DESC
  iam_policy_document = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:PutParameter"]
        Resource = [
          module.ssm_parameter_cluster_join_command.ssm_parameter_arn
        ]
      }
    ]
  }

  # Policy Attachment Config
  iam_policy_attachment_role_name = module.iam_role_control_plane.iam_role_name
}

/*
* --------------------------------------
* IAM POLICY FOR CONTROL PLANE S3 ACCESS
* --------------------------------------
* Grants the Control Plane permission to write the kubeconfig file to the secure S3 bucket.
* Ensures secure offloading of administrative credentials for external access.
*/
module "iam_policy_control_plane_s3_write" {
  source = "./modules/iam/policies"

  # Policy Config
  iam_policy_name        = local.IAM_POLICY_CP_S3_WRITE_NAME
  iam_policy_description = local.IAM_POLICY_CP_S3_WRITE_DESC
  iam_policy_document = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${module.s3_kubeconfig_bucket.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.s3_key.arn
      }
    ]
  }

  # Policy Attachment Config
  iam_policy_attachment_role_name = module.iam_role_control_plane.iam_role_name
}

/*
* -------------------------------------
* IAM POLICY FOR WORKER NODE SSM ACCESS
* -------------------------------------
* Grants Worker Nodes permission to read the cluster join command from SSM Parameter Store.
* Required for automated cluster joining during scaling events.
*/
module "iam_policy_worker_node_ssm_read" {
  source = "./modules/iam/policies"

  # Policy Config
  iam_policy_name        = local.IAM_POLICY_WN_SSM_READ_NAME
  iam_policy_description = local.IAM_POLICY_WN_SSM_READ_DESC
  iam_policy_document = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = module.ssm_parameter_cluster_join_command.ssm_parameter_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.s3_key.arn
      }
    ]
  }

  # Policy Attachment Config
  iam_policy_attachment_role_name = module.iam_role_worker_nodes.iam_role_name
}

/*
* ---------------------------------
* CONTROL PLANE LOAD BALANCER (NLB)
* ---------------------------------
* Provides a stable Network Load Balancer endpoint for the Kubernetes API Server.
* Ensures consistent connectivity for kubectl and worker nodes, abstracting the
* underlying EC2 instances managed by the Auto Scaling Group.
*/
module "control_plane_lb" {
  source = "./modules/load-balancer/nlb"

  # NLB Config
  nlb_name               = local.NLB_CP_NAME
  nlb_internal_enabled   = false
  nlb_cross_zone_enabled = true
  nlb_subnet_ids         = module.network.public_subnet_ids

  # NLB Target Group Config
  nlb_target_group_name = local.NLB_TG_CP_NAME
  nlb_target_port       = 6443
  nlb_target_protocol   = "TCP"
  nlb_target_vpc_id     = module.network.vpc_id

  # NLB Target Group Health Check Config
  nlb_target_health_check_protocol = "TCP"
  nlb_target_health_check_port     = 6443
  nlb_target_health_check_interval = 30

  # NLB Listener Config
  nlb_listener_port     = 6443
  nlb_listener_protocol = "TCP"
}

/*
* ----------------------------------
* KUBERNETES CONTROL PLANE RESOURCES
* ----------------------------------
* Provisions the Control Plane infrastructure using Auto Scaling Groups and Launch Templates.
* Bootstraps the Kubernetes cluster, installs networking components, and publishes
* connection info to SSM/S3.
*/
module "k8s_control_plane" {
  source = "./modules/compute"

  # Basic config
  ec2_name_prefix   = local.EC2_CP_NAME_PREFIX
  ec2_ami_id        = var.compute_k8s_instance_ami_id
  ec2_instance_type = var.compute_k8s_instance_type
  ec2_key_name      = var.compute_k8s_instance_ssh_key_name

  # Network config
  ec2_subnet_ids                  = module.network.public_subnet_ids
  ec2_security_group_ids          = [module.control_plane_security.sg_id]
  ec2_associate_public_ip_address = true

  # IAM config
  ec2_iam_instance_profile_name = aws_iam_instance_profile.iam_instance_profile_cp.name

  # User data to initialize the cluster
  ec2_user_data = templatefile("k8s_cp.sh", {
    lb_dns_name                         = module.control_plane_lb.nlb_dns_name,
    ssm_cluster_join_cmd_parameter_name = module.ssm_parameter_cluster_join_command.ssm_parameter_name,
    s3_bucket_name                      = module.s3_kubeconfig_bucket.s3_bucket_id,
    aws_region                          = var.main_aws_region
  })

  # Root volume config
  ec2_root_volume_size = 30
  ec2_root_volume_type = "gp3"

  # Auto scaling config
  ec2_asg_desired_capacity = 1
  ec2_asg_max_size         = 1
  ec2_asg_min_size         = 1

  # Attach ASG to the NLB Target Group
  ec2_target_group_arns = [module.control_plane_lb.nlb_target_group_arn]

  # Wait for succesful attachment of SSM Policy
  depends_on = [
    module.iam_policy_control_plane_ssm_write,
    module.iam_policy_control_plane_s3_write
  ]
}

/*
* ---------------------------------
* KUBERNETES WORKER NODES RESOURCES
* ---------------------------------
* Provisions Worker Node infrastructure using Auto Scaling Groups.
* Configures nodes to automatically discover the Control Plane via SSM and join
* the cluster to accept workloads.
*/
module "k8s_worker_nodes" {
  source = "./modules/compute"

  # Basic config
  ec2_name_prefix   = local.EC2_WN_NAME_PREFIX
  ec2_ami_id        = var.compute_k8s_instance_ami_id
  ec2_instance_type = var.compute_k8s_instance_type
  ec2_key_name      = var.compute_k8s_instance_ssh_key_name

  # Network config
  ec2_subnet_ids                  = module.network.private_subnet_ids
  ec2_security_group_ids          = [module.worker_node_security.sg_id]
  ec2_associate_public_ip_address = false

  # IAM config
  ec2_iam_instance_profile_name = aws_iam_instance_profile.iam_instance_profile_wn.name

  # User data to join the cluster
  ec2_user_data = templatefile("k8s_nodes.sh", {
    ssm_cluster_join_cmd_parameter_name = module.ssm_parameter_cluster_join_command.ssm_parameter_name,
    aws_region                          = var.main_aws_region
  })

  # Root volume config
  ec2_root_volume_size = 30
  ec2_root_volume_type = "gp3"

  # Auto scaling config
  ec2_asg_desired_capacity = 2
  ec2_asg_max_size         = 3
  ec2_asg_min_size         = 1

  # Wait for succesful attachment of SSM Policy
  depends_on = [
    module.iam_policy_worker_node_ssm_read
  ]
}
