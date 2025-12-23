#!/bin/bash
# -------------------------------------------------------
# Script Name  : k8s_instance_ami.sh
# Project Name : cSecBridge
# Description  : Automates the creation of a Golden AMI
#                for the Kubernetes Base Image
# Scope        : Infrastructure / AMI
# -------------------------------------------------------
# Exit immediately if a command exits with a non-zero status.
set -e
# Return the exit status of the last command in the pipe that failed.
set -o pipefail

# ----------------
# Global Variables
# ----------------
AWS_REGION="ap-southeast-1"
PROJECT_PREFIX="csecbridge"
TIMESTAMP=$(date +%Y%m%d%H%M)
AMI_NAME="${PROJECT_PREFIX}-k8s-base-${TIMESTAMP}"
INSTANCE_TYPE="t3.small"
USER_DATA_SCRIPT="k8s_user_data.sh"

# Base AMI: Amazon Linux 2023 (HVM) in ap-southeast-1
BASE_AMI_ID="ami-04c913012f8977029"

# Network Config (Leave empty to use default VPC/Subnet)
# If not specified, AWS uses the default VPC and a random subnet.
SUBNET_ID="" 
SECURITY_GROUP_ID=""

# Kubernetes Version
K8S_VERSION="v1.30"

# ----------------
# Custom Functions
# ----------------
# Log informational messages with timestamp and blue color
log_info() {
    echo -e "\033[1;34m[INFO] $(date '+%Y-%m-%d %H:%M:%S') : $1\033[0m"
}

# Log error messages with timestamp and red color
log_error() {
    echo -e "\033[1;31m[ERROR] $(date '+%Y-%m-%d %H:%M:%S') : $1\033[0m"
}

# Cleanup function to ensure the temporary builder instance is terminated
# regardless of script success or failure.
cleanup() {
    if [ -n "$INSTANCE_ID" ]; then
        log_info "Cleaning up: Terminating temporary instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" > /dev/null 2>&1
    fi
}

# Register cleanup trap to execute on script exit (EXIT signal)
trap cleanup EXIT

# --------------------------
# 1. Launch Builder Instance
# --------------------------
# Launches an EC2 instance that runs the user data script.
# Critical: 'instance-initiated-shutdown-behavior' is set to 'stop'.
# The user data script ends with 'shutdown -h now', which stops the instance.
# This stop signal indicates that provisioning is complete.

log_info "Launching temporary builder instance..."
log_info "Using User Data script: $USER_DATA_SCRIPT"

RUN_INSTANCES_CMD=(aws ec2 run-instances \
    --image-id "$BASE_AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --region "$AWS_REGION" \
    --user-data file://"$USER_DATA_SCRIPT" \
    --instance-initiated-shutdown-behavior stop \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_PREFIX}-k8s-ami-builder}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

# Add subnet/sg if specified
if [ -n "$SUBNET_ID" ]; then RUN_INSTANCES_CMD+=(--subnet-id "$SUBNET_ID"); fi
if [ -n "$SECURITY_GROUP_ID" ]; then RUN_INSTANCES_CMD+=(--security-group-ids "$SECURITY_GROUP_ID"); fi

INSTANCE_ID=$("${RUN_INSTANCES_CMD[@]}")
log_info "Builder instance launched: $INSTANCE_ID"

# ----------------------------------------
# 2. Wait for Provisioning (Instance Stop)
# ----------------------------------------
# Pauses execution until the instance enters the 'stopped' state.
# This confirms that the user data script has finished execution.
log_info "Waiting for instance to provision and stop (this may take 5-10 minutes)..."

# Wait for the instance to be running first.
# The 'instance-stopped' waiter considers 'pending' a failure state.
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
log_info "Instance $INSTANCE_ID has stopped. Provisioning complete."

# -------------
# 3. Create AMI
# -------------
# Create the Golden AMI from the stopped instance.
log_info "Creating AMI: $AMI_NAME..."
AMI_ID=$(aws ec2 create-image \
    --instance-id "$INSTANCE_ID" \
    --name "$AMI_NAME" \
    --description "Golden AMI for cSecBridge K8s Base (${K8S_VERSION})" \
    --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=$PROJECT_PREFIX},{Key=Role,Value=k8s-base}]" \
    --region "$AWS_REGION" \
    --query 'ImageId' \
    --output text)

log_info "AMI creation initiated: $AMI_ID"

# ----------------------------
# 4. Wait for AMI Availability
# ----------------------------
# The AMI creation is asynchronous. Waits for the AMI to be 'available' before use.
log_info "Waiting for AMI to become available..."
aws ec2 wait image-available --image-ids "$AMI_ID" --region "$AWS_REGION"
log_info "-------------------------------------------------------"
log_info "SUCCESS: K8s Base AMI created successfully."
log_info "AMI ID: $AMI_ID"
log_info "-------------------------------------------------------"

# ---------------------
# 5. Terminate Instance
# ---------------------
# Explicitly verify AMI state before cleaning up, though the trap would handle termination.
log_info "Verifying AMI existence before terminating instance..."

# Check if image exists and is available
AMI_STATE=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$AWS_REGION" --query 'Images[0].State' --output text)

if [ "$AMI_STATE" == "available" ]; then
    log_info "AMI $AMI_ID is available. Terminating builder instance $INSTANCE_ID..."
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" > /dev/null
else
    log_error "AMI $AMI_ID is not in 'available' state (State: $AMI_STATE). Instance $INSTANCE_ID will be handled by cleanup trap."
    exit 1
fi