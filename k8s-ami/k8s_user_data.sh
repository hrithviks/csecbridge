#!/bin/bash
# ----------------------------------------------------------------
# Script Name  : k8s_user_data.sh
# Description  : User Data script for K8s Base Golden AMI.
#                Installs dependencies, Containerd, and K8s tools.
#                Triggers shutdown upon completion for AMI creation.
# ----------------------------------------------------------------
set -e

# ---------------------------------
# 1. System Updates & Prerequisites
# ---------------------------------
echo "Updating system packages..."
dnf update -y
dnf install -y iproute-tc # Required for K8s networking (traffic control)

# -----------------------------------------
# 2. Install Container Runtime (Containerd)
# -----------------------------------------
echo "Installing Containerd..."
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Configure SystemdCgroup = true (Critical for Kubernetes 1.24+)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# ------------------------------------------------------------
# 3. Install Kubernetes Components (Kubelet, Kubeadm, Kubectl)
# ------------------------------------------------------------
echo "Installing Kubernetes components..."

# Add Kubernetes YUM repository (Targeting v1.30 stable)
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install tools (disable exclusion temporarily to install)
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# ----------------------
# 4. Finalize & Shutdown
# ----------------------
# The shutdown signal is detected by the AMI builder script to initiate image creation.
echo "Provisioning complete. Shutting down..."
shutdown -h now