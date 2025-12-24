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

# -----------------------------------------------------------------------------------
# Prerequisites: Enable IP Forwarding and Configure Local DNS Alias for Load Balancer
# -----------------------------------------------------------------------------------
echo "Enabling IP forwarding..."
modprobe br_netfilter
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "$PRIVATE_IP $LB_DNS_NAME" >> /etc/hosts

# --------------------------------------
# 1. Initialize Kubernetes Control Plane
# --------------------------------------
echo "Initializing Kubernetes control plane..."

# Initialize the cluster using kubeadm.
# - --control-plane-endpoint: Sets the stable Load Balancer DNS as the cluster entry point.
kubeadm init \
  --pod-network-cidr="$POD_NETWORK_CIDR" \
  --control-plane-endpoint="$LB_DNS_NAME:6443"

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
echo "Control plane initialization complete..."