#!/bin/bash
# -----------------------------------------------------------------------------
# Script Name  : devops-agent-user-data.sh
# Project Name : cSecBridge
# Description  : Bootstraps the EC2 instance for the self-hosted GitHub Actions
#                runner. It installs Docker, Git, and the GitHub Actions runner
#                agent, then configures and starts the runner service.
# Scope        : DevOps Infrastructure
# -----------------------------------------------------------------------------

# Install system dependencies
apt-get update -y
apt-get install -y docker.io git curl jq libdigest-sha-perl

# Configure Docker service
echo "Enabling Docker..."
systemctl enable docker
systemctl start docker
usermod -a -G docker ubuntu
chmod 666 /var/run/docker.sock

# Create directory for the runner agent
echo "Registering GitHub Actions runner..."
mkdir /home/ubuntu/actions-runner && cd /home/ubuntu/actions-runner

# Download and extract the runner agent
curl -o actions-runner-linux-x64-${github_agent_version}.tar.gz -L https://github.com/actions/runner/releases/download/v${github_agent_version}/actions-runner-linux-x64-${github_agent_version}.tar.gz
tar xzf ./actions-runner-linux-x64-${github_agent_version}.tar.gz

# Install runner dependencies
./bin/installdependencies.sh

# Configure and start the runner service
chown -R ubuntu:ubuntu /home/ubuntu/actions-runner
su - ubuntu -c "cd /home/ubuntu/actions-runner && ./config.sh --url https://github.com/${github_repository} --token ${github_runner_token} --unattended --name ${runner_name} --labels csec-self-hosted"
./svc.sh install ubuntu
./svc.sh start