#!/bin/bash

# -----------------------------------------------------------------------------
# CSecBridge AWS Worker - Functional Test Script
#
# This script automates the functional testing of the aws-worker service.
# It simulates a client sending requests to the api-service, which then get
# processed by the aws-worker. The script verifies the outcomes by checking
# the database and, where applicable, using the AWS CLI.
#
# It executes the following stages:
#   1. Verifies the test environment (kubectl, AWS CLI, dependent services).
#   2. Forwards the api-service port to localhost for easy access.
#   3. Runs a series of functional tests by sending `curl` requests.
#   4. Polls the database to check for job completion and status.
#   5. Verifies the outcome using the AWS CLI.
#   6. Reports the results and cleans up.
#
# Usage: ./run-aws-worker-tests.sh
# -----------------------------------------------------------------------------

# Global configuration
set -e
set -o pipefail # Exit on pipe failures
. ./set-test-libs.sh

# Test Configuration
CSB_NAMESPACE="csb-qa"
API_SERVICE_NAME="csb-api-service"
API_SERVICE_PORT="5000"
API_URL="http://localhost:${API_SERVICE_PORT}"
DB_POD_NAME=$(kubectl get pods -n "${CSB_NAMESPACE}" -l app=csb-postgres-service -o jsonpath='{.items[0].metadata.name}')

# Test Data
TEST_IAM_USER="csb-test-user-donotdelete"
TEST_IAM_ROLE="csb-test-role-donotdelete"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"

# --- Helper Functions ---

validate_environment() {
  log_info "Validating test environment..."
  local validation_passed=true

  if ! command -v kubectl &> /dev/null; then
    log_info "${RED}kubectl could not be found. Please install and configure it.${RESET}"
    validation_passed=false
  fi

  if ! command -v aws &> /dev/null; then
    log_info "${RED}AWS CLI could not be found. Please install and configure it.${RESET}"
    validation_passed=false
  fi

  if ! kubectl get svc "${API_SERVICE_NAME}" -n "${CSB_NAMESPACE}" &> /dev/null; then
    log_info "${RED}API service '${API_SERVICE_NAME}' not found in namespace '${CSB_NAMESPACE}'.${RESET}"
    validation_passed=false
  fi

  if [ -z "${DB_POD_NAME}" ]; then
    log_info "${RED}Postgres pod not found in namespace '${CSB_NAMESPACE}'.${RESET}"
    validation_passed=false
  fi

  if [ -z "${CSB_API_AUTH_TOKEN}" ]; then
    log_info "${RED}Environment variable CSB_API_AUTH_TOKEN is not set.${RESET}"
    validation_passed=false
  fi

  if [ "$validation_passed" = false ]; then
    log_info "${RED}Environment validation failed. Aborting.${RESET}"
    exit 1
  fi
  log_info "${GREEN}Environment validation successful.${RESET}"
}

setup_port_forward() {
  log_info "Setting up port-forward for the API service..."
  kubectl port-forward "svc/${API_SERVICE_NAME}" -n "${CSB_NAMESPACE}" "${API_SERVICE_PORT}:${API_SERVICE_PORT}" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
  # Allow time for port-forwarding to establish
  sleep 3
  if ! curl -s "${API_URL}/health"; then
      log_info "${RED}Failed to connect to API service via port-forward. Aborting.${RESET}"
      kill $PORT_FORWARD_PID
      exit 1
  fi
  log_info "Port-forward established to ${API_URL}"
}

teardown_environment() {
  log_info "Tearing down test environment..."
  if [ -n "$PORT_FORWARD_PID" ]; then
    log_info "Stopping port-forward..."
    kill "$PORT_FORWARD_PID"
  fi
  log_info "Teardown complete."
}

invoke_api() {
    local payload=$1
    local response
    response=$(curl -s -X POST "${API_URL}/access-request" \
        -H "Content-Type: application/json" \
        -H "X-Auth-Token: ${CSB_API_AUTH_TOKEN}" \
        -d "${payload}")
    
    if ! echo "${response}" | grep -q "request_id"; then
        log_failure "API Invocation" "Failed to get a valid request_id. Response: ${response}"
        return 1
    fi
    
    echo "${response}" | sed -n 's/.*"request_id": "\(.*\)".*/\1/p'
}

poll_db_for_status() {
    local request_id=$1
    local expected_status=$2
    local timeout=60 # seconds
    local interval=5 # seconds
    local elapsed=0
    local current_status=""

    log_info "Polling DB for request_id ${request_id} to reach status '${expected_status}'..."

    while [ $elapsed -lt $timeout ]; do
        current_status=$(kubectl exec -n "${CSB_NAMESPACE}" "${DB_POD_NAME}" -- \
            psql -U csb_admin -d csb_app_db -t -c \
            "SELECT status FROM access_requests WHERE request_id = '${request_id}';")
        
        # Trim whitespace
        current_status=$(echo "${current_status}" | xargs)

        if [ "${current_status}" == "${expected_status}" ]; then
            log_info "Status is '${expected_status}'. Polling successful."
            return 0
        fi

        if [[ "${current_status}" == "FAILED" || "${current_status}" == "ERROR" ]]; then
            log_info "${RED}Request failed with status '${current_status}'. Polling stopped.${RESET}"
            return 1
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_info "${RED}Timeout waiting for status '${expected_status}'. Last seen status: '${current_status}'.${RESET}"
    return 1
}

run_aws_worker_tests() {
    log_info "Starting AWS Worker Functional Tests..."
    local overall_status=0

    # ------------------------------------------------------------
    # AWS-TC-01: Attach S3 Read-Only Policy to Existing IAM User #
    # ------------------------------------------------------------
    log_info "Running: AWS-TC-01 - Attach policy to existing user"
    local payload_tc01='{"action": "grant", "principal_type": "user", "principal_name": "'"${TEST_IAM_USER}"'", "permission": "s3-read", "target_platform": "aws"}'
    local request_id_tc01
    if request_id_tc01=$(invoke_api "${payload_tc01}"); then
        if poll_db_for_status "${request_id_tc01}" "COMPLETED"; then
            run_test "AWS-TC-01 :: Verify policy attached to user" "success" \
                "aws iam list-attached-user-policies --user-name ${TEST_IAM_USER} | grep ${POLICY_ARN}"
        else
            overall_status=1
        fi
    else
        overall_status=1
    fi

    # ------------------------------------------------------------
    # AWS-TC-02: Revoke S3 Read-Only Policy from Existing IAM User #
    # ------------------------------------------------------------
    log_info "Running: AWS-TC-02 - Revoke policy from existing user"
    local payload_tc02='{"action": "revoke", "principal_type": "user", "principal_name": "'"${TEST_IAM_USER}"'", "permission": "s3-read", "target_platform": "aws"}'
    local request_id_tc02
    if request_id_tc02=$(invoke_api "${payload_tc02}"); then
        if poll_db_for_status "${request_id_tc02}" "COMPLETED"; then
            # We expect the command to fail (grep finds nothing)
            run_test "AWS-TC-02 :: Verify policy detached from user" "failure" \
                "aws iam list-attached-user-policies --user-name ${TEST_IAM_USER} | grep ${POLICY_ARN}"
        else
            overall_status=1
        fi
    else
        overall_status=1
    fi

    # ----------------------------------------------------------------
    # AWS-TC-03: Attach Policy to Non-Existing IAM User (should fail) #
    # ----------------------------------------------------------------
    log_info "Running: AWS-TC-03 - Attach policy to non-existing user"
    local payload_tc03='{"action": "grant", "principal_type": "user", "principal_name": "no-such-user-12345", "permission": "s3-read", "target_platform": "aws"}'
    local request_id_tc03
    if request_id_tc03=$(invoke_api "${payload_tc03}"); then
        # This should result in a FAILED status in the DB
        if ! poll_db_for_status "${request_id_tc03}" "FAILED"; then
            log_failure "AWS-TC-03" "Expected FAILED status but did not get it."
            overall_status=1
        else
            log_success "AWS-TC-03" "Correctly failed as expected."
        fi
    else
        overall_status=1
    fi

    return $overall_status
}

################
# Main program #
################

trap teardown_environment EXIT

validate_environment
setup_port_forward

if run_aws_worker_tests; then
  final_status=0
else
  final_status=$?
fi

if [ $final_status -eq 0 ]; then
  log_info "${GREEN}All AWS Worker functional tests passed successfully!${RESET}"
else
  log_info "${RED}One or more AWS Worker functional tests failed.${RESET}"
fi

log_info "Script finished."
exit $final_status