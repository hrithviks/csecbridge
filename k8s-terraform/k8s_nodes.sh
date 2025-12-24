#!/bin/bash
# ----------------------------------------------------------------
# Script Name  : k8s_nodes.sh
# Description  : User Data script for K8s Worker Node launch.
#                - Polls SSM Parameter Store for the join token.
#                - Joins the node to the Kubernetes cluster.
#                - Create a daemon to monitor worker node state.
# ----------------------------------------------------------------
set -e

# ----------------
# Global Variables
# ----------------
# These variables are injected by the Terraform templatefile() function.
SSM_CLUSTER_JOIN_PARAMETER_NAME="${ssm_cluster_join_cmd_parameter_name}"
AWS_REGION="${aws_region}"
STATE_FILE="/etc/kubeadm-join.last"

# --------------------------------------
# 0. Prerequisites: Enable IP Forwarding
# --------------------------------------
echo "Enabling IP forwarding..."
modprobe br_netfilter
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ----------------------------------------------------
# 1. Polls for Cluster Readiness and Joins Worker Node
# ----------------------------------------------------
# Executed only during the worker node launch.
echo "Starting worker node join process..."

while true; do
  echo "Polling SSM Parameter Store for join command..."
  # Use || echo "" to ensure the script doesn't exit if AWS CLI fails temporarily
  JOIN_COMMAND=$(aws ssm get-parameter --name "$SSM_CLUSTER_JOIN_PARAMETER_NAME" --with-decryption --query "Parameter.Value" --output text --region "$AWS_REGION" 2>/dev/null || echo "")

  if [[ -z "$JOIN_COMMAND" || "$JOIN_COMMAND" == "NOT_READY" ]]; then
    echo "Join command not yet available. Retrying in 15 seconds..."
    sleep 15
    continue
  fi

  echo "Join command retrieved. Attempting to join cluster..."

  # Attempt to join. We use 'if' to catch the exit code without triggering 'set -e'
  if eval $JOIN_COMMAND; then
    echo "Worker node has successfully joined the cluster."
    echo "$JOIN_COMMAND" > "$STATE_FILE"
    break
  else
    echo "Failed to join the cluster. This may happen if the token is expired or the Control Plane was replaced."
    echo "Resetting kubeadm state and retrying in 30 seconds..."

    # Reset node state to clean up failed join attempt
    kubeadm reset -f || true
    # Flush iptables to prevent stale networking rules
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

    # Clean up CNI configuration to prevent conflicts on retry
    rm -rf /etc/cni/net.d/*

    sleep 30
  fi
done

# ----------------------------------
# 2. Install Cluster Monitor Service
# ----------------------------------
# This service polls SSM to detect if the Control Plane has been replaced (new CA/Token).
# If the join command in SSM changes, it resets the node and rejoins.

echo "Installing worker node monitor service..."

cat <<EOF > /usr/local/bin/k8s-worker-monitor.sh
#!/bin/bash
SSM_PARAM_NAME="$SSM_CLUSTER_JOIN_PARAMETER_NAME"
REGION="$AWS_REGION"
CURRENT_CMD_FILE="$STATE_FILE"

while true; do
  # 1. Fetch latest join command from SSM
  NEW_CMD=\$(aws ssm get-parameter --name "\$SSM_PARAM_NAME" --with-decryption --query "Parameter.Value" --output text --region "\$REGION" 2>/dev/null || echo "")

  # 2. Check if valid
  if [[ -z "\$NEW_CMD" || "\$NEW_CMD" == "NOT_READY" ]]; then
    echo "Join command not ready. Waiting..."
    sleep 30
    continue
  fi

  # 3. Compare with current state
  if [[ -f "\$CURRENT_CMD_FILE" ]]; then
    CURRENT_CMD=\$(cat "\$CURRENT_CMD_FILE")
  else
    CURRENT_CMD=""
  fi

  if [[ "\$NEW_CMD" != "\$CURRENT_CMD" ]]; then
    echo "Cluster configuration changed (New Control Plane detected)."
    echo "Resetting node and re-joining..."
    
    kubeadm reset -f || true
    # Flush iptables and restart runtime to ensure clean slate
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
    rm -rf /etc/cni/net.d/*
    systemctl restart containerd
    
    if eval "\$NEW_CMD"; then
      echo "\$NEW_CMD" > "\$CURRENT_CMD_FILE"
      echo "Re-join successful."
    else
      echo "Re-join failed. Will retry next loop."
    fi
  fi

  sleep 60
done
EOF

chmod +x /usr/local/bin/k8s-worker-monitor.sh

# Create Systemd Unit
cat <<EOF > /etc/systemd/system/k8s-worker-monitor.service
[Unit]
Description=Kubernetes Worker Node Monitor
After=network-online.target

[Service]
ExecStart=/usr/local/bin/k8s-worker-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start the monitor
systemctl daemon-reload
systemctl enable --now k8s-worker-monitor.service
echo "Worker node initialization complete..."