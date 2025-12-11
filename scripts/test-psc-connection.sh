#!/bin/bash

# PSC Connection Test Script
# This script creates a Pod in a GKE cluster and tests access via PSC endpoint
#
# Usage:
#   ./scripts/test-psc-connection.sh [POD_NAME]
#
# Arguments:
#   POD_NAME: Test Pod name (optional, defaults to "test-psc-pod")
#
# Note: Project ID, cluster name, and location are automatically retrieved from Terraform outputs
#
# Examples:
#   ./scripts/test-psc-connection.sh
#   ./scripts/test-psc-connection.sh my-test-pod

set -e

# Retrieve values from Terraform outputs
echo "Retrieving configuration values from Terraform outputs..."
cd terraform

# Get project ID (always from Terraform)
if ! PROJECT_ID=$(terraform output -raw project_id 2>/dev/null); then
  echo "Error: Failed to retrieve project ID from Terraform output"
  echo "Please ensure Terraform apply has been executed"
  exit 1
fi

# Get Pod name (from first argument if provided)
if [ $# -ge 1 ] && [ -n "$1" ]; then
  POD_NAME="$1"
else
  POD_NAME="test-psc-pod"
fi

# Get cluster name and location
if ! CLUSTER_NAME=$(terraform output -raw gke_cluster_name 2>/dev/null); then
  echo "Error: Failed to retrieve GKE cluster name from Terraform output"
  exit 1
fi

if ! LOCATION=$(terraform output -raw gke_cluster_location 2>/dev/null); then
  echo "Error: Failed to retrieve GKE cluster location from Terraform output"
  exit 1
fi

# Get PSC endpoint IP
if ! PSC_ENDPOINT_IP=$(terraform output -raw psc_endpoint_ip 2>/dev/null); then
  echo "Error: Failed to retrieve PSC endpoint IP from Terraform output"
  exit 1
fi

cd ..

echo "Retrieved configuration values:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Cluster Name: ${CLUSTER_NAME}"
echo "  Location: ${LOCATION}"
echo "  Pod Name: ${POD_NAME}"
echo "  PSC Endpoint IP: ${PSC_ENDPOINT_IP}"
echo ""

echo "=========================================="
echo "PSC Connection Test"
echo "=========================================="

# Connect to GKE cluster
echo ""
echo "Connecting to GKE cluster..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --location ${LOCATION} \
  --project ${PROJECT_ID}

# Delete existing Pod if present
echo ""
echo "Checking for existing Pod..."
if kubectl get pod ${POD_NAME} &>/dev/null; then
  echo "Deleting existing Pod..."
  kubectl delete pod ${POD_NAME} --ignore-not-found=true
  sleep 5
fi

# Create test Pod (manifest embedded in script)
echo ""
echo "Creating test Pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  labels:
    app: test-psc
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 3600; done"]
  restartPolicy: Never
EOF

# Wait for Pod to be ready
echo ""
echo "Waiting for Pod to be ready..."
kubectl wait --for=condition=Ready pod/${POD_NAME} --timeout=120s

# Test access via PSC endpoint
echo ""
echo "=========================================="
echo "Testing Access via PSC Endpoint"
echo "=========================================="
echo "PSC Endpoint IP: ${PSC_ENDPOINT_IP}"
echo ""

# Get Pod IP for display
POD_IP=$(kubectl get pod ${POD_NAME} -o jsonpath='{.status.podIP}' 2>/dev/null || echo "N/A")

# Send HTTP request and capture output
echo "Sending HTTP request..."
echo ""

# Use a temporary file to capture curl output
TEMP_OUTPUT=$(mktemp)
kubectl exec ${POD_NAME} -- curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}\n" -m 10 http://${PSC_ENDPOINT_IP} > "$TEMP_OUTPUT" 2>&1
TEST_RESULT=$?

# Extract response body and HTTP code
HTTP_CODE=$(grep "^HTTP_CODE:" "$TEMP_OUTPUT" | cut -d: -f2 | tr -d '\r')
TIME_TOTAL=$(grep "^TIME_TOTAL:" "$TEMP_OUTPUT" | cut -d: -f2 | tr -d '\r')
RESPONSE_BODY=$(grep -v "^HTTP_CODE:" "$TEMP_OUTPUT" | grep -v "^TIME_TOTAL:" | grep -v "^$" | tr -d '\r')

# Clean up temp file
rm -f "$TEMP_OUTPUT"

echo ""
echo "=========================================="
echo "Connection Test Result"
echo "=========================================="
echo ""

# Display connection information
echo "📋 Connection Information:"
echo "  Source: GKE Pod (IP: ${POD_IP})"
echo "  Destination: PSC Endpoint (IP: ${PSC_ENDPOINT_IP})"
echo "  Target: AWS EC2 Instance (via VPN)"
echo ""

# Display response details
if [ $TEST_RESULT -eq 0 ] && [ -n "$HTTP_CODE" ]; then
  echo "✅ Connection Status: SUCCESS"
  echo ""
  echo "📊 Response Details:"
  echo "  HTTP Status Code: ${HTTP_CODE}"
  if [ -n "$TIME_TOTAL" ]; then
    echo "  Response Time: ${TIME_TOTAL}s"
  fi
  echo ""
  echo "📝 Response Body:"
  echo "  ┌─────────────────────────────────────────────────────────┐"
  if [ -n "$RESPONSE_BODY" ]; then
    echo "$RESPONSE_BODY" | sed 's/^/  │ /'
  else
    echo "  │ (Empty response)"
  fi
  echo "  └─────────────────────────────────────────────────────────┘"
  echo ""
  echo "🔗 Connection Path:"
  echo "  GKE Pod (${POD_IP})"
  echo "    ↓"
  echo "  PSC Endpoint (${PSC_ENDPOINT_IP})"
  echo "    ↓"
  echo "  Service Attachment"
  echo "    ↓"
  echo "  Internal Load Balancer (Producer VPC)"
  echo "    ↓"
  echo "  VPN Gateway (GCP → AWS)"
  echo "    ↓"
  echo "  AWS EC2 Instance ✅"
else
  echo "❌ Connection Status: FAILED"
  echo ""
  echo "Error Details:"
  if [ $TEST_RESULT -ne 0 ]; then
    echo "  curl command failed with exit code: $TEST_RESULT"
  fi
  if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" != "200" ]; then
    echo "  HTTP Status Code: ${HTTP_CODE:-N/A}"
  fi
  echo ""
  echo "Check the following:"
  echo "1. Verify PSC endpoint status is 'Accepted'"
  echo "2. Verify ILB backend (AWS EC2 instance) is running"
  echo "3. Verify firewall rules are correctly configured"
  echo "4. Verify VPN connection is established"
fi

# Delete Pod (regardless of success or failure)
echo ""
echo "Cleaning up test Pod..."
kubectl delete pod ${POD_NAME} --ignore-not-found=true
echo "Pod deleted"
echo ""

# Exit with appropriate code
if [ $TEST_RESULT -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Test completed successfully!"
  exit 0
else
  echo "❌ Test failed"
  exit 1
fi
