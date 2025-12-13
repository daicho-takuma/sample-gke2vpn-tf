# GCP GKE to AWS VPN via Private Service Connect

This project demonstrates how to connect a GKE cluster in GCP to an Amazon EC2 instance through a VPN connection using GCP's Private Service Connect (PSC) and Internal Load Balancer (ILB).

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        GCP (Consumer)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Consumer VPC                                        │   │
│  │  ┌──────────────┐  ┌──────────────────────────────┐ │   │
│  │  │ GKE Cluster  │  │  PSC Endpoint                │ │   │
│  │  │              │  │  (10.0.20.2)                 │ │   │
│  │  └──────────────┘  └──────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ PSC Connection
                            │
┌─────────────────────────────────────────────────────────────┐
│                        GCP (Producer)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Producer VPC                                        │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  Internal Load Balancer (ILB)                  │ │   │
│  │  │  └─> Service Attachment                        │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  VPN Gateway                                    │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ VPN Connection
                            │
┌─────────────────────────────────────────────────────────────┐
│                            AWS                                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16)                                    │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  VPN Gateway                                    │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  EC2 Instance (Private Subnet)                  │ │   │
│  │  │  IP: 10.0.20.10                                │ │   │
│  │  │  HTTP Server                                   │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### GCP Resources

- **Consumer VPC**: Hosts the GKE cluster and PSC endpoint
- **Producer VPC**: Hosts the ILB, Service Attachment, and VPN gateway
- **GKE Cluster**: Kubernetes cluster for testing PSC connectivity
- **PSC Endpoint**: Private Service Connect endpoint in Consumer VPC
- **Internal Load Balancer (ILB)**: Regional internal load balancer in Producer VPC
- **Service Attachment**: Exposes ILB via PSC
- **VPN Gateway**: Connects GCP Producer VPC to AWS VPC

### AWS Resources

- **VPC**: Virtual private cloud with public and private subnets
- **EC2 Instance**: Private instance running HTTP server
- **VPN Gateway**: Connects AWS VPC to GCP Producer VPC

## Prerequisites

### Required Tools

- Terraform >= 1.14.0
- AWS CLI configured with appropriate credentials
- GCP CLI (`gcloud`) configured with appropriate credentials
- kubectl installed

### Required Accounts and Permissions

- **GCP Project ID** with the following APIs enabled:
  - Compute Engine API
  - Kubernetes Engine API
  - Cloud Resource Manager API

- **AWS Account** with permissions to create:
  - VPC, Subnets, Internet Gateway, NAT Gateway
  - EC2 instances, Security Groups, Route Tables
  - VPN Gateway, Customer Gateway, VPN Connections
  - IAM Roles and Instance Profiles

### Enable GCP APIs

Before running Terraform, enable the required GCP APIs:

```bash
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

## Setup

### 1. Configure Terraform Variables

Copy the example variables file and set your project ID:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your GCP project ID:

```hcl
project_id = "your-gcp-project-id"
```

**Optional**: You can also override default values in `terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
environment  = "test"        # Optional: defaults to "test"
project_name = "gke2vpn"     # Optional: defaults to "gke2vpn"
aws_region   = "ap-northeast-1"  # Optional: defaults to "ap-northeast-1"
gcp_region   = "asia-northeast1" # Optional: defaults to "asia-northeast1"
```

**Note**: `terraform.tfvars` is already in `.gitignore` and will not be committed.

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Apply the Configuration

```bash
terraform apply
```

This will create the following resources:

**AWS Resources:**
- VPC with public and private subnets
- Amazon EC2 instance in private subnet (t2.small, running HTTP server on port 80)
- VPN Gateway and Customer Gateway
- Route tables and security groups
- IAM roles and instance profiles for EC2
- SSH key pair (automatically generated)

**GCP Resources:**
- Consumer VPC (hosts GKE cluster and PSC endpoint)
- Producer VPC (hosts ILB, Service Attachment, and VPN gateway)
- GKE cluster with auto-scaling node pool
- Internal Load Balancer (ILB)
- Service Attachment and PSC Endpoint
- VPN Gateway and External VPN Gateway

**Note**: 
- Resource creation typically takes 15-30 minutes
- VPN connection establishment may take an additional 10-20 minutes after resource creation
- Total setup time: approximately 25-50 minutes

### 5. Verify PSC Endpoint Status

Wait for the PSC endpoint status to become "Accepted":

```bash
cd terraform
PROJECT_ID=$(terraform output -raw project_id)
PSC_ENDPOINT_NAME=$(terraform output -raw psc_service_attachment_name | sed 's/.*\///')
REGION=$(terraform output -raw gke_cluster_location)

gcloud compute forwarding-rules describe ${PSC_ENDPOINT_NAME} \
  --region ${REGION} \
  --project ${PROJECT_ID}
```

## Testing PSC Connectivity

### Quick Test

Run the automated test script:

```bash
./scripts/test-psc-connection.sh
```

Or specify a custom Pod name:

```bash
./scripts/test-psc-connection.sh my-test-pod
```

This script will:
1. Retrieve configuration from Terraform outputs (project ID, cluster name, location, PSC endpoint IP)
2. Connect to the GKE cluster using `gcloud container clusters get-credentials`
3. Create a test Pod with a curl container
4. Test HTTP connectivity to the Amazon EC2 instance via PSC endpoint
5. Display detailed connection information including:
   - **Connection Information**: Source Pod IP, destination PSC endpoint IP, and target Amazon EC2 instance
   - **Response Details**: HTTP status code, response time, and response body
   - **Connection Path**: Visual representation of the connection path from GKE Pod to Amazon EC2 instance
6. Automatically clean up the test Pod

### Expected Output

When the connection is successful, you will see output similar to:

```
==========================================
Connection Test Result
==========================================

📋 Connection Information:
  Source: GKE Pod (IP: 10.0.100.23)
  Destination: PSC Endpoint (IP: 10.0.20.2)
  Target: Amazon EC2 Instance (via VPN)

✅ Connection Status: SUCCESS

📊 Response Details:
  HTTP Status Code: 200
  Response Time: 0.123s

📝 Response Body:
  ┌─────────────────────────────────────────────────────────┐
  │ Hello World from test-gke2vpn-aws-private-vm-01         │
  └─────────────────────────────────────────────────────────┘

🔗 Connection Path:
  GKE Pod (10.0.100.23)
    ↓
  PSC Endpoint (10.0.20.2)
    ↓
  Service Attachment
    ↓
  Internal Load Balancer (Producer VPC)
    ↓
  VPN Gateway (GCP → AWS)
    ↓
  Amazon EC2 Instance ✅
```

The script provides clear visual feedback about the connection status and helps troubleshoot any connectivity issues.

## Project Structure

```
.
├── terraform/                    # Terraform configuration files
│   ├── aws_*.tf                 # AWS resources (VPC, EC2, VPN)
│   ├── gcp_*.tf                 # GCP resources (VPC, GKE, ILB, PSC, VPN)
│   ├── locals.tf                # Local variables and configuration
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── provider.tf              # Provider configurations
│   ├── terraform.tf             # Terraform settings
│   └── terraform.tfvars.example # Example variables file
├── scripts/                      # Utility scripts
│   └── test-psc-connection.sh   # PSC connectivity test script with detailed output
├── misc/                         # Miscellaneous files
│   └── *.key.pub                # EC2 SSH public keys (generated by Terraform)
└── README.md                     # This file
```

**Note**: The following files are ignored by Git (via `.gitignore`):
- `terraform/terraform.tfvars` - Contains sensitive configuration (project ID, etc.)
- `terraform/terraform.tfstate*` - Terraform state files
- `misc/*.key` - Private SSH keys

## Configuration

### Default Settings

The following default values are configured in `terraform/locals.tf`:

- **Environment**: `test`
- **Project Name**: `gke2vpn`
- **AWS Region**: `ap-northeast-1`
- **GCP Region**: `asia-northeast1`
- **Amazon EC2 Instance Type**: `t2.small`
- **GKE Machine Type**: `e2-medium`
- **GKE Node Count**: 1-3 nodes (auto-scaling)
- **AWS VPC CIDR**: `10.0.0.0/16`
- **AWS Public Subnet**: `10.0.10.0/24`
- **AWS Private Subnet**: `10.0.20.0/24`
- **GKE Pod IP Range**: `10.0.100.0/24`
- **GKE Service IP Range**: `10.0.200.0/24`

**Note**: The GCP Consumer VPC intentionally uses overlapping CIDR ranges with AWS VPC to test VPN routing behavior. This is intentional for testing purposes.

To modify these settings, edit `terraform/locals.tf` before running `terraform apply`.

## Outputs

After applying Terraform, you can retrieve the following outputs:

```bash
cd terraform
terraform output
```

Available outputs:
- `project_id`: GCP Project ID
- `gke_cluster_name`: GKE cluster name
- `gke_cluster_location`: GKE cluster location
- `psc_endpoint_ip`: PSC endpoint IP address
- `psc_service_attachment_name`: Service attachment name

## Troubleshooting

### VPN Connection Issues

1. Check VPN tunnel status in both AWS and GCP consoles
2. Verify route tables and security groups
3. Ensure BGP sessions are established

### PSC Connection Issues

1. Verify PSC endpoint status is "Accepted"
2. Check ILB backend health
3. Verify firewall rules allow traffic
4. Check VPN connection is established between GCP and AWS
5. Verify the test script shows detailed error information:
   - If HTTP status code is not 200, check ILB backend and EC2 instance
   - If curl command fails, verify network connectivity and firewall rules

### GKE Cluster Issues

1. Verify cluster is running: `gcloud container clusters list`
2. Check node pool status
3. Review cluster logs in GCP Console

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete all resources created by Terraform, including:
- AWS VPC, subnets, EC2 instances, VPN gateways, and related resources
- GCP VPCs, GKE clusters, load balancers, VPN gateways, and related resources

**Note**: 
- Ensure you have backups of any important data before destroying resources
- The cleanup process may take 10-15 minutes
- Some resources (like VPN connections) may take time to fully terminate

## Cost Considerations

This project creates resources that incur costs in both AWS and GCP:

**AWS Costs:**
- EC2 instance (t2.small): ~$0.02-0.03/hour
- VPN Gateway: ~$0.05/hour
- Data transfer: varies by usage
- NAT Gateway (if used): ~$0.045/hour + data transfer

**GCP Costs:**
- GKE cluster: ~$0.10/hour (e2-medium nodes)
- VPN Gateway: ~$0.05/hour
- Load Balancer: ~$0.025/hour
- Data transfer: varies by usage

**Estimated Monthly Cost**: Approximately $50-100/month if left running continuously.

**Recommendation**: Destroy resources when not in use to avoid unnecessary costs.

## Security Considerations

- All sensitive values should be in `terraform.tfvars` (already in `.gitignore`)
- VPN connections use encrypted tunnels
- PSC provides private connectivity without exposing services to the internet
- Amazon EC2 instance is in a private subnet (no public IP)
- SSH keys for EC2 instances are automatically generated by Terraform
  - Private keys are stored in `misc/` directory (ignored by Git)
  - Public keys are stored in `misc/` directory and uploaded to AWS
- Review and adjust security groups and firewall rules as needed
- Ensure proper IAM permissions are configured for both AWS and GCP

## License

This is a sample project for demonstration purposes.

## Contributing

Contributions are welcome! Please ensure all code and documentation follow the existing style and include appropriate tests.
