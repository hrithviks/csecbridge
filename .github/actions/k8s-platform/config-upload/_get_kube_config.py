'''
PROGRAM : _get_kube_config.py
DESCR   : Generates a standalone kubeconfig file for a specific Kubernetes Service Account.
          This utility facilitates the extraction of cluster metadata and token generation
          to create portable credentials for CI/CD or external access.
'''

import argparse
import subprocess
import yaml
import sys
import re

def run_command(command):
    """
    Executes a shell command and returns the standard output.
    
    Args:
        command (list): The command and arguments to execute.
        
    Returns:
        str: The decoded stdout from the command.
    """
    try:
        # Architectural Decision: subprocess.run is utilized with shell=False to mitigate
        # shell injection vulnerabilities when handling user-provided arguments.
        process = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True
        )
        return process.stdout.strip()
    except FileNotFoundError:
        # Handles cases where the executable (e.g., kubectl) is not found in PATH
        print(f"Error: The command '{command[0]}' was not found. Please ensure it is installed and in your PATH.")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e.stderr}")
        sys.exit(1)

def generate_kubeconfig():
    """
    Generates a standalone kubeconfig file for a specific Service Account.
    """
    parser = argparse.ArgumentParser(description="Generate Kubeconfig for a Service Account")
    parser.add_argument("--service-account-name", required=True, help="Name of the Service Account")
    parser.add_argument("--namespace", default="default", help="Namespace of the Service Account")
    parser.add_argument("--token-ttl", default="8760h", help="Token duration (e.g., 24h, 8760h)")
    
    args = parser.parse_args()

    # Validate Service Account Name to prevent path traversal and ensure K8s compliance
    # Regex ensures DNS-1123 subdomain format (lowercase alphanumeric, '-' or '.')
    if not re.match(r'^[a-z0-9]([-a-z0-9]*[a-z0-9])?$', args.service_account_name):
        print(f"Error: Invalid Service Account name '{args.service_account_name}'. Must match DNS-1123 subdomain format.")
        sys.exit(1)

    # Extraction of cluster metadata from current admin context
    cluster_name = run_command(["kubectl", "config", "view", "--minify", "-o", "jsonpath={.clusters[0].name}"])
    server_url = run_command(["kubectl", "config", "view", "--minify", "-o", "jsonpath={.clusters[0].cluster.server}"])
    ca_data = run_command(["kubectl", "config", "view", "--minify", "--raw", "-o", "jsonpath={.clusters[0].cluster.certificate-authority-data}"])

    # Generation of the Service Account token
    # Architectural Decision: Using 'kubectl create token' ensures retrieval of a bound ServiceAccount token
    # rather than relying on long-lived secrets which are deprecated in newer K8s versions.
    token = run_command([
        "kubectl", "create", "token", 
        args.service_account_name, 
        "--namespace", args.namespace, 
        "--duration", args.token_ttl
    ])

    # Construction of the Kubeconfig structure
    kubeconfig_dict = {
        "apiVersion": "v1",
        "kind": "Config",
        "preferences": {},
        "clusters": [{
            "name": cluster_name,
            "cluster": {
                "certificate-authority-data": ca_data,
                "server": server_url
            }
        }],
        "contexts": [{
            "name": f"{args.service_account_name}-context",
            "context": {
                "cluster": cluster_name,
                "namespace": args.namespace,
                "user": args.service_account_name
            }
        }],
        "current-context": f"{args.service_account_name}-context",
        "users": [{
            "name": args.service_account_name,
            "user": {
                "token": token
            }
        }]
    }

    # Output to file
    file_name = f"{args.service_account_name}-config.yaml"
    with open(file_name, "w") as f:
        # Use safe_dump to ensure only standard YAML tags are output
        yaml.safe_dump(kubeconfig_dict, f, default_flow_style=False)

    print(f"Successfully generated: {file_name}")

if __name__ == "__main__":
    generate_kubeconfig()