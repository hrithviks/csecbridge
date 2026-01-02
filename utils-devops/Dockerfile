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
ARG TFLINT_VERSION="v0.50.3"
ARG TRIVY_VERSION="0.50.1"
ARG TFSEC_VERSION="v1.28.6"
ARG KUBECONFORM_VERSION="v0.6.4"

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

# Install TFLint
RUN curl -LO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" && \
    unzip tflint_linux_amd64.zip && \
    mv tflint /usr/local/bin/

# Install Trivy
RUN curl -LO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    tar xzf "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" && \
    mv trivy /usr/local/bin/

# Install tfsec
RUN curl -LO "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-amd64" && \
    chmod +x tfsec-linux-amd64 && \
    mv tfsec-linux-amd64 /usr/local/bin/tfsec

# Install Kubeconform
RUN curl -LO "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" && \
    tar xzf "kubeconform-linux-amd64.tar.gz" && \
    mv kubeconform /usr/local/bin/

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
COPY --from=builder /usr/local/bin/tflint /usr/local/bin/tflint
COPY --from=builder /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=builder /usr/local/bin/tfsec /usr/local/bin/tfsec
COPY --from=builder /usr/local/bin/kubeconform /usr/local/bin/kubeconform
COPY --from=builder /aws-cli-bin/ /usr/local/bin/

# Verify installations
RUN terraform --version && \
    kubectl version --client && \
    aws --version && \
    tflint --version && \
    trivy --version && \
    tfsec --version && \
    kubeconform -v

# Set default entrypoint
CMD ["/bin/bash"]