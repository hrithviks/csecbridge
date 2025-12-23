#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name : build-runner-image.sh
# Description : Automates the build and publication of the custom Docker image
#               used for CI/CD pipelines.
#               1. Validates environment credentials.
#               2. Builds the Docker image using the local Dockerfile.
#               3. Authenticates with GitHub Container Registry (GHCR).
#               4. Pushes the image to the registry.
# Usage       : ./build-runner-image.sh
# -----------------------------------------------------------------------------
set -e
set -o pipefail

# ----------------
# Global Variables
# ----------------
IMAGE_NAME="csecbridge-runner-image"
IMAGE_TAG="latest"
DOCKER_CONTEXT="."

# ----------------------
# Environment Validation
# ----------------------
echo "Validating environment configuration..."

if [ -z "${GH_USER}" ]; then
    echo "Error: GH_USER environment variable is not set."
    exit 1
fi

if [ -z "${GH_TOKEN}" ]; then
    echo "Error: GH_TOKEN environment variable is not set."
    exit 1
fi

FULL_IMAGE_URI="ghcr.io/${GH_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

# -------------
# Build Process
# -------------
echo "Starting Docker build..."
echo "Target Image: ${FULL_IMAGE_URI}"

docker build -t "${FULL_IMAGE_URI}" "${DOCKER_CONTEXT}"

# ---------------------
# Push to GHCR Registry
# ---------------------
echo "Authenticating with GitHub Container Registry..."
echo "${GH_TOKEN}" | docker login ghcr.io -u "${GH_USER}" --password-stdin

echo "Pushing image to registry..."
docker push "${FULL_IMAGE_URI}"
echo "-----------------------------------------------------------------------"
echo "Build and Push Complete."
echo "Image URI: ${FULL_IMAGE_URI}"
echo "-----------------------------------------------------------------------"