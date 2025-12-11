#########################
# Basic Configuration
#########################
locals {
  env        = var.environment
  project    = var.project_name
  project_id = var.project_id
}

#########################
# AWS Configuration
#########################

# AWS Network Config
locals {
  aws_network_config = {
    region   = var.aws_region
    vpc_name = "${local.env}-${local.project}-aws-vpc"
    vpc_cidr = "10.0.0.0/16"
    public_subnet = {
      "${local.env}-${local.project}-aws-public-subnet-apn1-a" = {
        az   = "ap-northeast-1a"
        cidr = "10.0.10.0/24"
      }
    }
    private_subnet = {
      "${local.env}-${local.project}-aws-private-subnet-apn1-a" = {
        az   = "ap-northeast-1a"
        cidr = "10.0.20.0/24"
      }
    }
  }
}

# AWS Instance Config
locals {
  aws_instance_config = {
    ec2_public = {
    }
    ec2_private = {
      "${local.env}-${local.project}-aws-private-vm-01" = {
        az            = "ap-northeast-1a"
        type          = "t2.small"
        private_ip    = "10.0.20.10"
        key_name      = "${local.env}-${local.project}-ec2-user-key"
        sg_name       = "${local.env}-${local.project}-web-sg"
        subnet_name   = "${local.env}-${local.project}-aws-private-subnet-apn1-a"
        protected     = false
        vol_type      = "gp3"
        vol_size      = "10"
        vol_encrypted = true
      }
    }
  }
}

# AWS VPN Config
locals {
  aws_vpn_config = {
    asn = 65001
  }
}

#########################
# GCP Configuration
#########################

# GCP Consumer Network Config
# Consumer VPC: For GKE cluster and PSC endpoint
# IMPORTANT: This VPC intentionally uses the SAME CIDR ranges as AWS VPC to test VPN routing behavior
# when both sides have overlapping IP address spaces. This is intentional for testing purposes.
locals {
  gcp_consumer_network_config = {
    region   = var.gcp_region
    vpc_name = "${local.env}-${local.project}-gcp-consumer-vpc"
    general_subnet = {
      # Primary subnet for GKE nodes (VMs)
      # This CIDR is used for the node IP addresses (not Pods/Services)
      # ⚠️ INTENTIONAL OVERLAP: Using SAME CIDR as AWS public subnet to test VPN routing
      # AWS public subnet: ${local.aws_network_config.public_subnet[keys(local.aws_network_config.public_subnet)[0]].cidr}
      "${local.env}-${local.project}-gcp-consumer-gke-subnet" = {
        region = var.gcp_region
        cidr   = local.aws_network_config.public_subnet[keys(local.aws_network_config.public_subnet)[0]].cidr # Same as AWS public subnet: 10.0.10.0/24
      }
      # ⚠️ INTENTIONAL OVERLAP: Using SAME CIDR as AWS private subnet to test VPN routing
      # AWS private subnet: ${local.aws_network_config.private_subnet[keys(local.aws_network_config.private_subnet)[0]].cidr}
      "${local.env}-${local.project}-gcp-consumer-psc-endpoint-subnet" = {
        region = var.gcp_region
        cidr   = local.aws_network_config.private_subnet[keys(local.aws_network_config.private_subnet)[0]].cidr # Same as AWS private subnet: 10.0.20.0/24
      }
    }
    # Secondary IP ranges for GKE cluster subnet (defined as secondary_ip_range in the subnet)
    # These are separate IP ranges used within the same subnet:
    # - Pods: IP addresses assigned to each Pod container
    # - Services: IP addresses for Kubernetes Services (ClusterIP)
    # ⚠️ INTENTIONAL OVERLAP: These ranges are within AWS VPC CIDR (${local.aws_network_config.vpc_cidr})
    #   to test VPN routing behavior with overlapping IP spaces
    # Note: These ranges must NOT overlap with:
    #   - Primary subnet CIDR (10.0.10.0/24 - same as AWS public subnet)
    #   - PSC endpoint subnet CIDR (10.0.20.0/24 - same as AWS private subnet)
    #   - Each other (Pod and Service ranges must not overlap)
    # Pods: /24 provides ~250 IPs (sufficient for testing/validation purposes)
    # Services: /24 provides ~250 IPs (sufficient for testing/validation purposes)
    # Both ranges are within AWS VPC (10.0.0.0/16) but do not overlap with:
    #   - AWS subnets (10.0.10.0/24, 10.0.20.0/24)
    #   - Each other (Pods and Services ranges are separate)
    gke_pod_ip_range     = "10.0.100.0/24" # Secondary range: for Pod IPs (10.0.100.0 - 10.0.100.255, within AWS VPC 10.0.0.0/16, sufficient for testing)
    gke_service_ip_range = "10.0.200.0/24" # Secondary range: for Service IPs (10.0.200.0 - 10.0.200.255, within AWS VPC 10.0.0.0/16, sufficient for testing)
  }
}

# GCP Producer Network Config
# Producer VPC: For ILB, Service Attachment, and VPN
locals {
  gcp_producer_network_config = {
    region   = var.gcp_region
    vpc_name = "${local.env}-${local.project}-gcp-producer-vpc"
    general_subnet = {
      "${local.env}-${local.project}-gcp-producer-psc-nat-subnet" = {
        region = var.gcp_region
        cidr   = "10.10.10.0/24"
      }
      "${local.env}-${local.project}-gcp-producer-ilb-frontend-subnet" = {
        region = var.gcp_region
        cidr   = "10.10.20.0/24"
      }
    }
    proxy_subnet = {
      "${local.env}-${local.project}-gcp-producer-ilb-proxy-subnet" = {
        region = var.gcp_region
        cidr   = "10.10.30.0/24"
      }
    }
  }
}

# GCP GKE Config
locals {
  gcp_gke_config = {
    cluster_name   = "${local.env}-${local.project}-gke-cluster"
    location       = var.gcp_region
    node_pool_name = "${local.env}-${local.project}-gke-node-pool"
    machine_type   = "e2-medium"
    min_node_count = 1
    max_node_count = 3
    initial_count  = 1
    subnet_name    = "${local.env}-${local.project}-gcp-consumer-gke-subnet"
  }
}

# GCP VPN Config
locals {
  gcp_vpn_config = {
    asn = 65000
  }
}

# GCP Zone Config
# Derive zone from region (using first zone, typically -a)
locals {
  gcp_zone = "${var.gcp_region}-a"
}
