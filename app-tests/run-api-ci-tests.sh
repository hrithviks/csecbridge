#!/bin/bash

# -----------------------------------------------------------------------------
# CSecBridge API Service - CI Process Validation Script
#
# This script automates the validation of the core CI/CD mechanics for the
# api-service, including linting, containerization, and deployment. It is
# designed to be run locally to test the automation itself.
#
# It executes the following stages:
#   1. Verifies that the prerequisite Kubernetes environment exists.
#   2. Runs linting tests (both success and failure cases).
#   3. Runs Docker build tests (both success and failure cases).
#   4. Runs Helm deployment tests (success, template error, runtime error).
#   5. Generates a report in the console.
#   6. Tears down all test-specific resources created by the script.
#
# Usage: ./run-api-tests.sh
# -----------------------------------------------------------------------------

# Set environment variables
. .env-api-service

# Global configuration
set -o pipefail # Exit on pipe failures
. ./set-test-libs.sh

# Test configuration for QA environment
CSB_NAMESPACE="csb-qa"
CSB_SA_NAME="csb-app-sa"
CSB_ROLE_NAME="csb-app-deployer-role"
CSB_API_SERVICE_PATH="../app-api-service"
CSB_API_HELM_CHART_PATH="${CSB_API_SERVICE_PATH}/helm"
CSB_API_RELEASE_NAME="csb-api-rel"
CSB_DB_SERVICE="csb-postgres-service"
CSB_REDIS_SERVICE="csb-redis-service"
CSB_API_SERVICE_PORT="5000"
CSB_API_URL="http://localhost:${CSB_API_SERVICE_PORT}"

# Environment setup function
validate_environment() {

  log_info "Verifying test environment configuration data..."
  # Environment variable for build section
  if [ -z "${GH_USER}" ] || [ -z "${GH_TOKEN}" ]; then
    log_info "${RED}Environment vars missing for the containerization section...${RESET}"
    exit 1
  fi

  # Environment variables for kubernetes secrets
  if [ -z "${CSB_API_AUTH_TOKEN}" ] || [ -z "${CSB_POSTGRES_PSWD}" ] || [ -z "${CSB_REDIS_DEF_PSWD}" ]; then
    log_info "${RED}Environment vars missing for the kubernetes secrets section...${RESET}"
    exit 1
  fi

  # Environment variables for building database objects
  if [ -z $CSB_DB_APP_USER ] || [ -z $CSB_DB_APP_PSWD ] || [ -z $CSB_DB_NAME ]; then
    log_info "${RED}Environment vars missing for deploying postgres database objects...${RESET}"
  fi

  # Environment variables for redis ACL
  if [ -z $CSB_API_REDIS_USER ] || [ -z $CSB_API_REDIS_PSWD ] || [ -z $CSB_REDIS_DEF_PSWD ]; then
    log_info "${RED}Environment vars missing for setting Redis ACL...${RESET}"
  fi

  # Platform configuration
  log_info "Verifying test platform..."
  if ! kubectl get namespace "$CSB_NAMESPACE" > /dev/null 2>&1; then
    log_info "${RED}Prerequisites missing: Namespace '${CSB_NAMESPACE}' does not exist...${RESET}"
    log_info "${RED}Please apply platform config before running tests...${RESET}"
    exit 1
  fi

  if ! kubectl get serviceaccount "$CSB_SA_NAME" -n "$CSB_NAMESPACE" > /dev/null 2>&1; then
    log_info "${RED}Prerequisites missing: ServiceAccount '${CSB_SA_NAME}' does not exist...${RESET}"
    log_info "${RED}Please apply platform config before running tests...${RESET}"
    exit 1
  fi

  if ! kubectl get role "$CSB_ROLE_NAME" -n "$CSB_NAMESPACE" > /dev/null 2>&1; then
    log_info "${RED}Prerequisites missing: Role '${CSB_ROLE_NAME}' does not exist...${RESET}"
    log_info "${RED}Please apply platform config before running tests...${RESET}"
    exit 1
  fi

  # Backend services configuration
  log_info "Verifying backend services..."

  # Check postgres service
  if ! kubectl get service $CSB_DB_SERVICE -n $CSB_NAMESPACE | grep '5432/TCP' > /dev/null 2>&1; then
    log_info "${RED}Prerequisites missing: Service '${CSB_DB_SERVICE}' not configured for port 5432...${RESET}"
  fi

  # Check redis service
  if ! kubectl get service $CSB_REDIS_SERVICE -n $CSB_NAMESPACE | grep '6379/TCP' > /dev/null 2>&1; then
    log_info "${RED}Prerequisites missing: Service '${CSB_REDIS_SERVICE}' not configured for port 6379...${RESET}"
  fi

  log_info "Test environment is ready..."
}

teardown_environment() {
  log_info "Tearing down test resources..."

  if [ -n "$PORT_FORWARD_PID" ]; then
    log_info "Stopping port-forward..."
    kill "$PORT_FORWARD_PID"
  fi

  # Use --ignore-not-found to prevent errors during cleanup
  helm uninstall "${CSB_API_RELEASE_NAME}" -n "${CSB_NAMESPACE}" --ignore-not-found=true > /dev/null 2>&1
  
  log_info "Teardown complete."
}

run_ci_tests() {
  log_info "Simulating CI/CD Process Validation Tests..."
  local overall_status=0

  #############################################
  # Section 1: Code Quality Check and Linting #
  #############################################

  # CI-01: Test lint success
  log_info "Section 1: Code Quality & SAST Tests..."
  if ! run_test "CI-01  :: Python Linting" "success" "flake8 ${CSB_API_SERVICE_PATH}/src/"; then
    overall_status=1
  fi
  
  # CI-02: Test SAST success
  # Bandit will exit with 0 if no issues are found.
  # We can add `-ll` to only report on medium+ severity issues.
  if ! run_test "CI-02  :: Python SAST (Bandit)" "success" "bandit -r ${CSB_API_SERVICE_PATH}/src/ -ll"; then
    overall_status=1
  fi

  # CI-03: Test Dependency Scan (Trivy)
  # Trivy will exit with 0 if no vulnerabilities of the specified severity are found.
  if ! run_test "CI-03  :: Dependency Scan (Trivy)" "success" "trivy fs --scanners vuln --severity HIGH,CRITICAL ${CSB_API_SERVICE_PATH}"; then
    overall_status=1
  fi

  # test-ci.py is pre-configured to introduce vulnerabilities and linting errors
  local ci_test_file="./test-docs/test-ci.py"
  cp "${ci_test_file}" "${CSB_API_SERVICE_PATH}/src/"

  # CI-04: Test SAST failure - by introducing a known vulnerability
  if ! run_test "CI-04  :: Python SAST (Bandit - Failure)" "failure" "bandit -r ${CSB_API_SERVICE_PATH}/src/ -ll"; then
    overall_status=1
  fi

  # CI-05: Test lint failure using the same test file
  if ! run_test "CI-05  :: Python Linting (Failure)" "failure" "flake8 ${CSB_API_SERVICE_PATH}/src/"; then
    overall_status=1
  fi

  # Clean up test file(s)
  rm -f "${CSB_API_SERVICE_PATH}/src/test-ci.py"

  ###############################
  # Section 2: Containerization #
  ###############################
  log_info "Section 2: Containerization Tests..."

  # Local Env Vars for Testing
  local DOCKERFILE_PATH=${CSB_API_SERVICE_PATH}
  local IMAGE_NAME="csb-api-qa"
  local IMAGE_TAG="latest"
  local GHCR_IMAGE="ghcr.io/${GH_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

  # CI-06: Test build success
  if ! run_test "CI-06  :: Docker Image Build" "success" "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ${DOCKERFILE_PATH}"; then
    overall_status=1
  fi

  # CI-07: Test image for vulnerabilities
  # This will fail if HIGH or CRITICAL vulnerabilities are found.
  if ! run_test "CI-07  :: Image Vulnerability Scan (Trivy)" "success" "trivy image --scanners vuln --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}"; then
    overall_status=1
  fi

  # CI-08: Test docker login(Section A) and push to github container registry(Section B)
  if ! run_test "CI-08A :: GitHub Container Registry Login" "success" "docker login ghcr.io -u ${GH_USER} -p ${GH_TOKEN}"; then
    overall_status=1
  else
    # If login successful, tag and test push
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "$GHCR_IMAGE" 2>/dev/null
    if ! run_test "CI-08B :: Image Push to GitHub Container Registry" "success" "docker push ${GHCR_IMAGE}"; then
      overall_status=1
    fi
  fi

  # CI-09: Test build failure - by introducing a syntax error in the Dockerfile
  sed -i.bak 's/COPY/COPPY/' "${CSB_API_SERVICE_PATH}/Dockerfile"
  if ! run_test "CI-09  :: Docker Image Build (Failure)" "failure" "docker build -t csb-api-qa-fail:latest ${CSB_API_SERVICE_PATH}"; then
    overall_status=1
  fi

  # Clean up the modified Dockerfile
  git restore "${CSB_API_SERVICE_PATH}/Dockerfile"
  if [ $? -eq 0 ]; then
    rm -f "${CSB_API_SERVICE_PATH}/Dockerfile.bak"
  fi
  
  ###############################
  # Section 3: Kubernetes Tests #
  ###############################
  log_info "Section 3: Kubernetes Tests..."

  # This command mimics a CI/CD pipeline securely creating secrets for db-user, redis-user and api-token
  # Secret names and keys are hardcoded in the helm's values.yaml file.
  # Secret values are passed as environment variables (secrets on a pipeline)

  # CI-10 : Create Kubernetes Secret for Backend Database User
  if ! run_test "CI-10  :: Kubernetes DB Secret Creation" "success" "kubectl create secret generic csb-postgres-api-user-secret \
    --from-literal=csb-api-user-pswd="${CSB_POSTGRES_PSWD}" \
    --namespace=${CSB_NAMESPACE} \
    --dry-run=client \
    -o yaml | kubectl apply -f - > /dev/null 2>&1"; then
    log_info "${RED}Failed to create kubernetes secret for admin password...${RESET}"
    return 127
  fi
  
  # CI-11 : Check Kubernetes Secret for Backend Database User
  if ! run_test "CI-11  :: Kubernetes DB Secret Check" "success" "kubectl get secret csb-postgres-api-user-secret -n ${CSB_NAMESPACE}"; then
    log_info "${RED}Failed to get kubernetes secret for admin password...${RESET}"
    return 127
  fi

  # CI-12 : Create Kubernetes Secret for Backend Redis Client User
  if ! run_test "CI-12  :: Kubernetes Redis Secret Creation" "success" "kubectl create secret generic csb-redis-user-secret \
    --from-literal=csb-api-redis-pswd="${CSB_API_REDIS_PSWD}" \
    --namespace=${CSB_NAMESPACE} \
    --dry-run=client \
    -o yaml | kubectl apply -f - > /dev/null 2>&1"; then
    log_info "${RED}Failed to create kubernetes secret for Redis client password...${RESET}"
    return 127
  fi
  
  # CI-13 : Check Kubernetes Secret for Backend Redis User
  if ! run_test "CI-13  :: Kubernetes Redis Secret Check" "success" "kubectl get secret csb-redis-user-secret -n ${CSB_NAMESPACE}"; then
    log_info "${RED}Failed to get kubernetes secret for Redis client password...${RESET}"
    return 127
  fi

  # CI-14 : Create Kubernetes Secret for API Token
  if ! run_test "CI-14  :: Kubernetes API Token Secret Creation" "success" "kubectl create secret generic csb-api-token-secret \
    --from-literal=csb-api-token="${CSB_API_AUTH_TOKEN}" \
    --namespace=${CSB_NAMESPACE} \
    --dry-run=client \
    -o yaml | kubectl apply -f - > /dev/null 2>&1"; then
    log_info "${RED}Failed to create kubernetes secret for admin password...${RESET}"
    return 127
  fi
  
  # CI-15 : Check Kubernetes Secret for API Token
  if ! run_test "CI-15  :: Kubernetes API Token Secret Check" "success" "kubectl get secret csb-api-token-secret -n ${CSB_NAMESPACE}"; then
    log_info "${RED}Failed to get kubernetes secret for admin password...${RESET}"
    return 127
  fi

  # This command mimics a CI/CD pipeline securely creating the secret for github token
  # Secret name is "csb-gh-secret"
  # Secret type is a Docker registry secret, comprising of username, access token and server name

  # CI-16 : Kubernetes GH Token Secret Creation
  if ! run_test "CI-16  :: Kubernetes Image Secret Creation" "success" "kubectl create secret docker-registry csb-gh-secret \
    --docker-server="ghcr.io" \
    --docker-username="${GH_USER}" \
    --docker-password="${GH_TOKEN}" \
    --namespace=${CSB_NAMESPACE} \
    --dry-run=client \
    -o yaml | kubectl apply -f - > /dev/null 2>&1"; then
    log_info "${RED}Failed to create kubernetes secret for image token...${RESET}"
    return 127
  fi
  
  # CI-17 : Kubernetes Check Secret - GH Token
  if ! run_test "CI-17  :: Kubernetes Image Secret Check" "success" "kubectl get secret csb-gh-secret -n ${CSB_NAMESPACE}"; then
    log_info "${RED}Failed to get kubernetes secret for image token...${RESET}"
    return 127
  fi

  #######################################
  # Section 4: Backend Deployment Tests #
  #######################################
  log_info "Section 4: Backend Deployment Tests"

  # Get pod names for backend services
  local db_pod_name
  db_pod_name=$(kubectl get pods -n "${CSB_NAMESPACE}" -l app.kubernetes.io/name=csb-postgres-service -o jsonpath='{.items[0].metadata.name}')
  local redis_pod_name
  redis_pod_name=$(kubectl get pods -n "${CSB_NAMESPACE}" -l app.kubernetes.io/name=csb-redis-service -o jsonpath='{.items[0].metadata.name}')

  # CI-18: Execute backend.sql on postgreSQL database to create tables
  # Firstly, it copies the local script into the pod under a temporary location.
  # After copying, it executes the psql command using the temporary file.
  kubectl cp ${CSB_API_SERVICE_PATH}/sql/backend.sql -n ${CSB_NAMESPACE} ${db_pod_name}:/tmp/backend.sql

  local psql_exec_cmd="kubectl exec -n ${CSB_NAMESPACE} ${db_pod_name} -- \
    env PGPASSWORD='${CSB_DB_APP_PSWD}' psql -U '${CSB_DB_APP_USER}' -d '${CSB_DB_NAME}' -f /tmp/backend.sql"

  if ! run_test "CI-18  :: Deploy Database Objects (Tables)" "success" "${psql_exec_cmd}"; then
    log_info "${RED}Failed to deploy database objects. Aborting further tests.${RESET}"
    return 1
  fi

  # CI-19: Execute ACL for "csb_api_client" on Redis
  # This sets the password and permissions for the API service's Redis user.
  # It runs 'ACL SET' to configure the user and 'ACL SAVE' to persist the
  # changes to the ACL file on disk, making them durable across restarts.
  local redis_acl_set="redis-cli ACL SETUSER ${CSB_API_REDIS_USER} \>${CSB_API_REDIS_PSWD} ON allkeys +@all"
  local redis_acl_save="redis-cli ACL SAVE"
  local redis_acl_cmd="kubectl exec -n ${CSB_NAMESPACE} ${redis_pod_name} -- \
    env REDISCLI_AUTH=${CSB_REDIS_DEF_PSWD} sh -c \"${redis_acl_set} && ${redis_acl_save}\""

  if ! run_test "CI-19  :: Configure Redis User ACL" "success" "${redis_acl_cmd}"; then
    log_info "${RED}Failed to configure Redis ACLs. Aborting further tests.${RESET}"
    return 1
  fi

  ######################################
  # Section 5: Helm Installation Tests #
  ######################################
  log_info "Section 5: Helm Installation Tests"

  # CI-20 : Helm Installation Test for API-Service
  if ! run_test "CI-20  :: Helm Installation Test" "success" "helm upgrade \
  --install ${CSB_API_RELEASE_NAME} ${CSB_API_HELM_CHART_PATH} \
  --namespace ${CSB_NAMESPACE} \
  --set statefulset.image.uri=${GHCR_IMAGE} \
  --wait --timeout=5m > /tmp/api_helm_install_$$.log 2>&1"; then
    log_info "${RED}Failed to deploy helm chart...${RESET}"
    return 127
  fi
  sleep 5

  # CI-21 : Helm Installation Check
  if ! run_test "CI-21  :: Helm Installation Validation" "success" "helm list \
  -A -n ${CSB_NAMESPACE} | grep ${CSB_API_RELEASE_NAME}"; then
    log_info "${RED}Failed to validate helm chart deployment...${RESET}"
    return 127
  fi

  ########################################
  # Section 6: Kubernetes Resource Tests #
  ########################################
  log_info "Section 6: Kubernetes Resources Tests, post deployment"

  # Local variables for the section
  local API_CONFIGMAP="csb-api-service-config"
  local API_SERVICE_NAME="csb-api-service"
  local API_DEPLOYMENT_NAME="csb-api-service"

  # CI-22 : Check if the ConfigMap exists for the service
  # This is a basic validation. Additional validation should include check for
  # all the configurations required for the service.
  if ! run_test "CI-22  :: API-Service Kubernetes Config Map Validation" "success" "kubectl \
  get configmap ${API_CONFIGMAP} -n ${CSB_NAMESPACE}"; then
    log_info "${RED}Failed to validate the ConfigMap...${RESET}"
    overall_status=1
  fi

  # CI-23 : Check if the ClusterIP Service Exists
  if ! run_test "CI-23  :: API-Service Kubernetes ClusterIP Service Validation" "success" "kubectl \
  get service ${API_SERVICE_NAME} -n ${CSB_NAMESPACE} > /dev/null 2>&1"; then
    log_info "${RED}Failed to validate the ClusterIP Service...${RESET}"
    overall_status=1
  fi

  # CI-24 : Check if the StatefulSet is ready
  # This is a simple validation, testing the existence of the statefulset.
  # Parse the response to perform advanced validations.
  if ! run_test "CI-24  :: API-Service Kubernetes Deployment Validation" "success" "kubectl \
  get deployment ${API_DEPLOYMENT_NAME} -n ${CSB_NAMESPACE} > /dev/null 2>&1"; then
    log_info "${RED}Failed to validate the StatefulSet...${RESET}"
    overall_status=1
  fi

  # CI-25 : Check if the POD is Running
  # Note: This is a very basic check for the POD status for API service.    
  if [ `kubectl get pod -n ${CSB_NAMESPACE} | grep ${API_SERVICE_NAME} | wc -l` -gt 0 ]; then
    if ! run_test "CI-25  :: API-Service Kubernetes POD Validation" "success" "kubectl \
    get pod -n ${CSB_NAMESPACE} | grep ${API_SERVICE_NAME}- | grep Running > /dev/null 2>&1"; then
      log_info "${RED}Failed to validate the POD status...${RESET}"
      overall_status=1
    fi
  else
    log_info "${RED}Failed to validate the required POD Replica (>0)...${RESET}"
    overall_status=1
  fi

  #######################################
  # Section 7: API Functional Tests     #
  #######################################
  log_info "Section 7: API Functional Tests"

  # CI-26: Port forward to the service
  #log_info "Setting up port-forward for the API service..."
  #kubectl port-forward "svc/${API_SERVICE_NAME}" -n "${CSB_NAMESPACE}" "${CSB_API_SERVICE_PORT}":8000 >/dev/null 2>&1 && \
  #PORT_FORWARD_PID=$!
  # Allow time for port-forwarding to establish
  #sleep 3
  #if ! run_test "CI-26  :: API Service Port-Forward" "success" "curl -s ${CSB_API_URL}/health"; then
  #    log_info "${RED}Failed to connect to API service via port-forward. Aborting functional tests.${RESET}"
  #    overall_status=1
  #    return $overall_status
  #fi

  # CI-27: Check API Health Endpoint
  if ! run_test "CI-27  :: API Health Endpoint Check" "success" "curl -s ${CSB_API_URL}/health | jq -e '.status' | grep 'ok' > /dev/null"; then
    overall_status=1
  fi

  # CI-28: Check API POST /api/v1/request Endpoint
  local payload="./test-docs/test_payload.json"
  local response
  response=$(curl -s -X POST "${CSB_API_URL}/api/v1/requests" \
      -H "Content-Type: application/json" \
      -H "X-Auth-Token: ${CSB_API_AUTH_TOKEN}" \
      -d "@${payload}")
  
  if ! run_test "CI-28  :: API POST /api/v1/request Endpoint" "success" "echo $response | grep 'correlation_id'"; then
    log_info "Response was: ${response}"
    overall_status=1
  else
    correlation_id=$(echo $response | jq -e '.correlation_id' | tr -d '"')
  fi

  # CI-29: Check API GET /api/v1/request Endpoint
  local response
  response=$(curl -s -X GET "${CSB_API_URL}/api/v1/requests/${correlation_id}" \
      -H "Content-Type: application/json" \
      -H "X-Auth-Token: ${CSB_API_AUTH_TOKEN}")
  
  if ! run_test "CI-29  :: API GET /api/v1/request Endpoint" "success" "echo $response | grep 'status'"; then
    log_info "Response was: ${response}"
    overall_status=1
  fi

  # CI-30: Submit an invalid access request (missing field)
  local invalid_payload="./test-docs/test_payload_err.json"
  local response
  response=$(curl -s -X POST "${CSB_API_URL}/api/v1/requests" \
      -H "Content-Type: application/json" \
      -H "X-Auth-Token: ${CSB_API_AUTH_TOKEN}" \
      -d "@${invalid_payload}")
  
  if ! run_test "CI-30  :: API POST /api/v1/request Endpoint (Failure)" "failure" "echo $response | jq -e '.correlation_id'"; then
    overall_status=1
  fi

  #########################################
  # Section 8: Backend Validation Tests   #
  #########################################
  log_info "Section 8: Backend Validation Tests"

  # correlation_id from CI-28 will be used to validate the backend.

  if [ -z "${correlation_id}" ]; then
      log_info "${RED}Could not extract request_id from previous test. Aborting backend validation.${RESET}"
      overall_status=1
      return $overall_status
  fi

  # CI-30: Verify the request was inserted into the database with PENDING status
  local db_pod_name
  db_pod_name=$(kubectl get pods -n "${CSB_NAMESPACE}" -l app.kubernetes.io/name=csb-postgres-service -o jsonpath='{.items[0].metadata.name}')
  local psql_command="kubectl exec -n ${CSB_NAMESPACE} ${db_pod_name} -- env PGPASSWORD=${CSB_DB_APP_PSWD} psql -U ${CSB_DB_APP_USER} -d ${CSB_DB_NAME} -t -c \"SELECT status FROM csb_app.csb_requests WHERE correlation_id = '${correlation_id}';\""
  
  if ! run_test "CI-30  :: Database Record Insertion" "success" "${psql_command} | grep -q 'PENDING'"; then
    overall_status=1
  fi

  # CI-31: Verify the job was pushed to the Redis queue
  local redis_pod_name
  redis_pod_name=$(kubectl get pods -n "${CSB_NAMESPACE}" -l app.kubernetes.io/name=csb-redis-service -o jsonpath='{.items[0].metadata.name}')
  # We use RPOP to retrieve the item and remove it so it doesn't affect other tests
  local redis_command="kubectl exec -n ${CSB_NAMESPACE} ${redis_pod_name} -- env REDISCLI_AUTH=${CSB_API_REDIS_PSWD} redis-cli -u redis://${CSB_API_REDIS_USER}:${CSB_API_REDIS_PSWD}@localhost:6379 RPOP aws:worker_queue"
  
  if ! run_test "CI-31  :: Redis Queue Job Creation" "success" "${redis_command} | grep -q ${correlation_id}"; then
    overall_status=1
  fi

  # CI-32: Verify the cache is empty (cache is populated on first GET, not on creation)
  local redis_cache_command="kubectl exec -n ${CSB_NAMESPACE} ${redis_pod_name} -- env REDISCLI_AUTH=${CSB_REDIS_PSWD} redis-cli GET cache:status:${correlation_id}"
  if ! run_test "CI-32  :: Redis Cache State (Should be empty)" "success" "[ -z \"\$(${redis_cache_command} 2>/dev/null)\" ]"; then
    overall_status=1
  fi

  return $overall_status
}

################
# Main program #
################

# NOTE: To inspect created resources after a test run, comment out the teardown section in "trap"
# Ensures teardown runs even if the script is interrupted (e.g., with Ctrl+C)
# trap teardown_environment EXIT

validate_environment
run_ci_tests
final_status=$?

if [ $final_status -eq 0 ]; then
  log_info "${GREEN}All CI validation tests passed successfully!${RESET}"
elif [ $final_status -eq 1 ]; then
  log_info "${RED}One or more CI validation tests failed.${RESET}"
else
  log_info "${RED}Testing interrupted due to misconfiguration.${RESET}"
fi

# The 'trap' will handle the final teardown automatically on exit.
log_info "Script finished."
exit $final_status