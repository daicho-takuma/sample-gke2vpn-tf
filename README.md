# GCP GKE to AWS VPN via Private Service Connect

This project demonstrates how to connect a GKE cluster in GCP to an AWS EC2 instance through a VPN connection using GCP's Private Service Connect (PSC) and Internal Load Balancer (ILB).

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

- Terraform >= 1.14.0
- AWS CLI configured with appropriate credentials
- GCP CLI (`gcloud`) configured with appropriate credentials
- kubectl installed
- GCP Project ID
- AWS Account with permissions to create VPC, EC2, VPN resources

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

This will create:
- AWS VPC, subnets, EC2 instance, and VPN gateway
- GCP Consumer and Producer VPCs
- GCP GKE cluster
- GCP Internal Load Balancer
- GCP Service Attachment and PSC Endpoint
- VPN connection between AWS and GCP

**Note**: VPN connection establishment may take 10-20 minutes.

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

See [k8s/README.md](k8s/README.md) for detailed testing instructions.

### Quick Test

Run the automated test script:

```bash
./scripts/test-psc-connection.sh
```

This script will:
1. Retrieve configuration from Terraform outputs
2. Connect to the GKE cluster
3. Create a test Pod
4. Test HTTP connectivity to the AWS EC2 instance via PSC
5. Automatically clean up the test Pod

## Project Structure

```
.
├── terraform/           # Terraform configuration files
│   ├── aws_*.tf        # AWS resources (VPC, EC2, VPN)
│   ├── gcp_*.tf        # GCP resources (VPC, GKE, ILB, PSC, VPN)
│   ├── locals.tf       # Local variables and configuration
│   ├── variables.tf    # Input variables
│   ├── outputs.tf      # Output values
│   └── provider.tf     # Provider configurations
├── scripts/            # Utility scripts
│   └── test-psc-connection.sh  # PSC connectivity test script
├── k8s/                 # Kubernetes-related documentation
│   └── README.md       # PSC testing guide
└── src/                 # Source code (optional)
    └── curl-golang/     # Sample HTTP server (not used in main flow)
```

## Configuration

### Default Settings

- **Environment**: `test`
- **Project Name**: `gke2vpn`
- **AWS Region**: `ap-northeast-1`
- **GCP Region**: `asia-northeast1`
- **GKE Machine Type**: `e2-medium`
- **GKE Node Count**: 1-3 nodes (auto-scaling)

These can be modified in `terraform/locals.tf`.

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
4. See [k8s/README.md](k8s/README.md) for detailed troubleshooting

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

**Warning**: This will delete all resources created by Terraform, including VPCs, instances, and load balancers.

## Security Considerations

- All sensitive values should be in `terraform.tfvars` (already in `.gitignore`)
- VPN connections use encrypted tunnels
- PSC provides private connectivity without exposing services to the internet
- EC2 instance is in a private subnet
- Review and adjust security groups and firewall rules as needed

## License

This is a sample project for demonstration purposes.

## Contributing

Contributions are welcome! Please ensure all code and documentation follow the existing style and include appropriate tests.
