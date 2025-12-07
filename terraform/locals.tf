#########################
# Basic Configuration
#########################
locals {
  env        = "test"
  project    = "gke2vpn"
  project_id = var.project_id
}

#########################
# AWS Configuration
#########################

# AWS Network Config
locals {
  aws_network_config = {
    region   = "ap-northeast-1"
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
# Consumer VPC: GKEクラスターとPSCエンドポイント用
locals {
  gcp_consumer_network_config = {
    region   = "asia-northeast1"
    vpc_name = "${local.env}-${local.project}-gcp-consumer-vpc"
    general_subnet = {
      "${local.env}-${local.project}-gcp-consumer-gke-subnet" = {
        region = "asia-northeast1"
        cidr   = "10.0.10.0/24"
      }
      "${local.env}-${local.project}-gcp-consumer-psc-endpoint-subnet" = {
        region = "asia-northeast1"
        cidr   = "10.0.20.0/24"
      }
    }
  }
}

# GCP Producer Network Config
# Producer VPC: ILB、Service Attachment、VPN用
locals {
  gcp_producer_network_config = {
    region   = "asia-northeast1"
    vpc_name = "${local.env}-${local.project}-gcp-producer-vpc"
    general_subnet = {
      "${local.env}-${local.project}-gcp-producer-psc-nat-subnet" = {
        region = "asia-northeast1"
        cidr   = "10.10.10.0/24"
      }
      "${local.env}-${local.project}-gcp-producer-ilb-frontend-subnet" = {
        region = "asia-northeast1"
        cidr   = "10.10.20.0/24"
      }
    }
    proxy_subnet = {
      "${local.env}-${local.project}-gcp-producer-ilb-proxy-subnet" = {
        region = "asia-northeast1"
        cidr   = "10.10.30.0/24"
      }
    }
  }
}

# GCP GKE Config
locals {
  gcp_gke_config = {
    cluster_name   = "${local.env}-${local.project}-gke-cluster"
    location       = "asia-northeast1"
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
