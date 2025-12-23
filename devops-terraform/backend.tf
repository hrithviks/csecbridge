/*
 * Script Name  : backend.tf
 * Project Name : cSecBridge
 * Description  : Configures S3 backend for state storage and native S3 locking to prevent concurrent modifications.
 * Scope        : Root
 */

terraform {
  backend "s3" {
    bucket       = "csec-app-infra-backend"
    key          = "devops-cluster/devops.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
