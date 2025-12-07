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

# Send HTTP request
echo "Sending HTTP request..."
TEST_RESULT=0
kubectl exec ${POD_NAME} -- curl -v -m 10 http://${PSC_ENDPOINT_IP} || TEST_RESULT=$?

echo ""
echo "=========================================="
echo "Connection Test Result"
echo "=========================================="

# Delete Pod (regardless of success or failure)
echo ""
echo "Deleting test Pod..."
kubectl delete pod ${POD_NAME} --ignore-not-found=true
echo "Pod deleted"

# Display test result
if [ $TEST_RESULT -eq 0 ]; then
  echo "✅ Connection successful!"
  exit 0
else
  echo "❌ Connection failed"
  echo ""
  echo "Check the following:"
  echo "1. Verify PSC endpoint status is 'Accepted'"
  echo "2. Verify ILB backend (AWS EC2 instance) is running"
  echo "3. Verify firewall rules are correctly configured"
  exit 1
fi
