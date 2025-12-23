/*
* Main section variables
*/
main_aws_region     = "ap-southeast-1"
main_cluster_name   = "dev"
main_project_prefix = "csec"
main_default_tags = {
  project     = "csec-bridge"
  application = "csec-app-infra-cluster"
  created     = "21-Dec-2025"
  contact     = "admin@csecbridge.org"
  environment = "dev"
}

/*
* Network section variables
*/
network_vpc_cidr = "10.0.0.0/16"
network_public_subnets_cidr = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]
network_private_subnets_cidr = [
  "10.0.10.0/24",
  "10.0.11.0/24"
]
network_availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b"
]

/*
* Compute section variables
*/
compute_control_plane_iam_role_policy = {
  Version = "2012-10-17"
  Statement = [
    {
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
    }
  ]
}
compute_worker_nodes_iam_role_policy = {
  Version = "2012-10-17"
  Statement = [
    {
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
    }
  ]
}
compute_k8s_instance_ami_id       = "ami-0d97009afb6707d71"
compute_k8s_instance_type         = "t3.small"
compute_k8s_instance_ssh_key_name = "csec-ssh-key-pair"
