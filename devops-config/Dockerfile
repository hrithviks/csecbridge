# -----------------------------------------------------------------------------
# Dockerfile for Custom CI/CD Runner Agent
# Description: Defines a multi-stage build for a minimalistic Docker image
#              equipped with essential DevOps tools (Terraform, Kubectl, AWS CLI).
#              Designed for use within GitHub Actions workflows.
# -----------------------------------------------------------------------------

# ----------------
# Stage 1: Builder
# ----------------
# Downloads and extracts binaries. Uses a temporary builder stage to keep the
# final image layer clean and minimal.
FROM debian:stable-slim AS builder

ARG TERRAFORM_VERSION="1.14.2"
ARG KUBECTL_VERSION="v1.34.0"

# Install build dependencies
RUN apt-get update && apt-get install -y curl unzip

# Install Terraform
RUN curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    mv terraform /usr/local/bin/

# Install Kubectl
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install --bin-dir /aws-cli-bin/ --install-dir /usr/local/aws-cli

# --------------------
# Stage 2: Final Image
# --------------------
# Assembles the runtime image by copying binaries from the builder stage and
# installing only necessary runtime dependencies.
FROM debian:stable-slim

# Install runtime dependencies
# - ca-certificates: Required for HTTPS connections (AWS CLI, Terraform, Curl)
# - git: Required for checking out repositories
# - jq: Required for JSON processing in pipelines
# - less, groff: Required for AWS CLI output formatting
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    jq \
    curl \
    less \
    groff && \
    rm -rf /var/lib/apt/lists/*

# Copy binaries from builder
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/terraform
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/aws-cli /usr/local/aws-cli
COPY --from=builder /aws-cli-bin/ /usr/local/bin/

# Verify installations
RUN terraform --version && \
    kubectl version --client && \
    aws --version

# Set default entrypoint
CMD ["/bin/bash"]