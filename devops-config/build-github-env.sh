#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name : build-github-env.sh
# Description : Automates the provisioning of GitHub Environments and
#               Environment Variables using the GitHub CLI (gh).
#               Ensures idempotency by creating or updating resources.
# Usage       : ./build-github-env.sh
# -----------------------------------------------------------------------------
set -e
set -o pipefail

# ----------------
# Global Variables
# ----------------
# List of environments to provision based on workflows
ENVIRONMENTS=("devops" "platform-dev" "platform-qa" "infra-dev" "infra-qa" "app-dev" "app-qa")

# Configuration Values
AWS_REGION="ap-southeast-1"
IMAGE_NAME="csecbridge-runner-image"
IMAGE_TAG="latest"
REPO_OWNER="hrithviks"
REPO_FULL_NAME="hrithviks/csecbridge"

# --------------
# Initial Checks
# --------------
echo "Validating environment configuration..."

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub. Please run 'gh auth login'."
    exit 1
fi

if [ -z "${GH_TOKEN}" ] \
    || [ -z "${GH_USER}" ] \
    || [ -z "${AWS_ACCOUNT_ID}" ] \
    || [ -z "${AWS_OIDC_ROLE_INFRA}" ] \
    || [ -z "${AWS_OIDC_ROLE_PLATFORM}" ] \
    || [ -z "${AWS_S3_TFVAR_BUCKET}" ]; then
    echo "Error: Environment variables for secrets not set. Exiting!"
    exit 1
fi

# ----------------
# Custom Functions
# ----------------

# Set Infrastructure Secrets
set_infra_secrets() {
    echo "Setting Infrastructure Secrets..."
    local env_name=$(echo $1 | awk -F'-' '{print $2}') 

    # Set AWS_ACCOUNT_ID Secret
    echo "Setting Secret: AWS_ACCOUNT_ID"
    gh secret set AWS_ACCOUNT_ID --body "${AWS_ACCOUNT_ID}" --env "$1"

    # Set AWS_OIDC_ROLE Secret
    echo "Setting Secret: AWS_OIDC_ROLE"
    gh secret set AWS_OIDC_ROLE --body "${AWS_OIDC_ROLE_INFRA}-${env_name}" --env "$1"

    # Set AWS_S3_TFVAR_BUCKET Secret
    echo "Setting Secret: AWS_S3_TFVAR_BUCKET"
    gh secret set AWS_S3_TFVAR_BUCKET --body "${AWS_S3_TFVAR_BUCKET}" --env "$1"
}

# Set Platform Secrets
set_platform_secrets() {
    echo "Setting Platform Secrets..."
    local env_name=$(echo $1 | awk -F'-' '{print $2}')

    # Set AWS_ACCOUNT_ID Secret
    echo "Setting Secret: AWS_ACCOUNT_ID"
    gh secret set AWS_ACCOUNT_ID --body "${AWS_ACCOUNT_ID}" --env "$1"

    # Set AWS_OIDC_ROLE Secret
    echo "Setting Secret: AWS_OIDC_ROLE"
    gh secret set AWS_OIDC_ROLE --body "${AWS_OIDC_ROLE_PLATFORM}-${env_name}" --env "$1"
}

# Set Application Secrets
set_app_secrets() {
    echo "Setting Application Secrets..."
    local env_name=$(echo $1 | awk -F'-' '{print $2}')
}

# Construct the Runner Image URI
RUNNER_IMAGE_URI="ghcr.io/${REPO_OWNER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Target Repository : ${REPO_FULL_NAME}"
echo "Runner Image URI  : ${RUNNER_IMAGE_URI}"

# -----------------
# Environment Setup
# -----------------
echo "Starting Environment provisioning..."

for ENV_NAME in "${ENVIRONMENTS[@]}"; do
    echo "-----------------------------------------------------------------------"
    echo "Processing Environment: ${ENV_NAME}"

    # 1. Create or Update Environment
    # Using 'gh api' with PUT is idempotent for environment creation
    echo "Ensuring environment exists..."
    gh api --method PUT "repos/${REPO_FULL_NAME}/environments/${ENV_NAME}" --silent

    # 2. Set AWS_REGION Variable
    echo "Setting Variable: AWS_REGION = ${AWS_REGION}"
    # 'gh variable set' creates or updates the variable
    gh variable set AWS_REGION --body "${AWS_REGION}" --env "${ENV_NAME}"

    # 3. Set GH_RUNNER_IMAGE Variable
    echo "Setting Variable: GH_RUNNER_IMAGE = ${RUNNER_IMAGE_URI}"
    gh variable set GH_RUNNER_IMAGE --body "${RUNNER_IMAGE_URI}" --env "${ENV_NAME}"

    # 4. Set GH_TOKEN Secret
    echo "Setting Secret: GH_TOKEN"
    gh secret set GH_TOKEN --body "${GH_TOKEN}" --env "${ENV_NAME}"

    # 5. Set GH_USER Secret
    echo "Setting Secret: GH_USER"
    gh secret set GH_USER --body "${GH_USER}" --env "${ENV_NAME}"

    if [[ "${ENV_NAME}" =~ ^platform- ]]; then
        set_platform_secrets "${ENV_NAME}"
    elif [[ "${ENV_NAME}" =~ ^infra- ]]; then
        set_infra_secrets "${ENV_NAME}"
    elif [[ "${ENV_NAME}" =~ ^app- ]]; then
        set_app_secrets "${ENV_NAME}"
    else
        continue
    fi
done

echo "-----------------------------------------------------------------------"
echo "GitHub Environment setup complete."
echo "-----------------------------------------------------------------------"