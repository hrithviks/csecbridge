#!/bin/bash
# ----------------------------------------------------------------
# Script Name  : k8s_cp.sh
# Description  : User Data script for K8s Control Plane launch.
#                - Initializes the cluster with kubeadm.
#                - Installs Calico CNI.
#                - Publishes the join token to SSM Parameter Store.
# ----------------------------------------------------------------
set -e

# ----------------
# Global Variables
# ----------------
# These variables are injected by the Terraform templatefile() function.
LB_DNS_NAME="${lb_dns_name}"
SSM_CLUSTER_JOIN_PARAMETER_NAME="${ssm_cluster_join_cmd_parameter_name}"
S3_BUCKET_NAME="${s3_bucket_name}"
AWS_REGION="${aws_region}"
POD_NETWORK_CIDR="192.168.0.0/16" # For Calico

# --------------------------------------
# 1. Initialize Kubernetes Control Plane
# --------------------------------------
echo "Initializing Kubernetes control plane..."

# Retrieve the public IP for the API server certificate.
# This allows kubectl access from outside the VPC.
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Initialize the cluster using kubeadm.
# - --control-plane-endpoint: Sets the stable Load Balancer DNS as the cluster entry point.
# - --apiserver-cert-extra-sans: Adds the instance's Public IP to the certs for direct debugging access.
kubeadm init \
  --pod-network-cidr="$POD_NETWORK_CIDR" \
  --control-plane-endpoint="$LB_DNS_NAME:6443" \
  --apiserver-cert-extra-sans=$PUBLIC_IP

# ---------------------------------
# 2. Configure kubectl for ec2-user
# ---------------------------------
echo "Configuring kubectl for ec2-user..."

mkdir -p /home/ec2-user/.kube
cp -i /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube

# --------------------------------------------
# 3. Install Container Network Interface (CNI)
# --------------------------------------------
echo "Installing Calico CNI..."

# Apply the Calico manifests. The cluster nodes will remain in a 'NotReady'
# state until a CNI is installed and running.
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# ------------------------------------
# 4. Generate and Publish Join Command
# ------------------------------------
echo "Generating and publishing worker join command to SSM..."

# Create a new join token and command.
JOIN_COMMAND=$(kubeadm token create --print-join-command)

# Publish the full join command to SSM Parameter Store.
# The '--overwrite' flag handles cases where a new control plane is created.
aws ssm put-parameter \
  --name "$SSM_CLUSTER_JOIN_PARAMETER_NAME" \
  --value "$JOIN_COMMAND" \
  --type "SecureString" \
  --overwrite \
  --region "$AWS_REGION"

# ---------------------------
# 5. Upload Kubeconfig to S3
# ---------------------------
echo "Uploading admin kubeconfig to S3..."
aws s3 cp /etc/kubernetes/admin.conf s3://$S3_BUCKET_NAME/kube-admin.conf
echo "Control plane initialization complete."