#########################
# Consumer VPC
# GKEクラスターとPSCエンドポイント用
#########################
resource "google_compute_network" "consumer_vpc" {
  name                    = local.gcp_consumer_network_config.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  mtu                     = 1460
}

resource "google_compute_subnetwork" "consumer_subnet" {
  for_each      = local.gcp_consumer_network_config.general_subnet
  name          = each.key
  ip_cidr_range = each.value.cidr
  region        = each.value.region
  network       = google_compute_network.consumer_vpc.id

  # Add secondary IP ranges for GKE cluster subnet only
  # Secondary IP ranges are used for Pods and Services, while the primary CIDR
  # is used for the GKE node VMs themselves.
  # 
  # Network architecture:
  # - Primary range: GKE node VMs get IPs from here
  #   ⚠️ INTENTIONAL OVERLAP: Same CIDR as AWS public subnet (${local.aws_network_config.public_subnet[keys(local.aws_network_config.public_subnet)[0]].cidr})
  #   This is intentional to test VPN routing behavior with overlapping IP spaces
  # - Secondary range "pods" (10.0.100.0/24): Each Pod gets an IP from here (10.0.100.0 - 10.0.100.255)
  #   ⚠️ INTENTIONAL OVERLAP: Within AWS VPC CIDR (${local.aws_network_config.vpc_cidr}), sufficient for testing
  # - Secondary range "services" (10.0.200.0/24): Kubernetes Services get IPs from here (10.0.200.0 - 10.0.200.255)
  #   ⚠️ INTENTIONAL OVERLAP: Within AWS VPC CIDR (${local.aws_network_config.vpc_cidr}), sufficient for testing
  dynamic "secondary_ip_range" {
    # Only add secondary IP ranges for the GKE cluster subnet
    # Check if subnet name ends with "-gke-subnet" to identify GKE subnet
    for_each = endswith(each.key, "-gke-subnet") ? [
      {
        range_name    = "pods"
        ip_cidr_range = local.gcp_consumer_network_config.gke_pod_ip_range
      },
      {
        range_name    = "services"
        ip_cidr_range = local.gcp_consumer_network_config.gke_service_ip_range
      }
    ] : []
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}

#########################
# Producer VPC
# ILB、Service Attachment、VPN用
#########################
resource "google_compute_network" "producer_vpc" {
  name                    = local.gcp_producer_network_config.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  mtu                     = 1460
}

resource "google_compute_subnetwork" "producer_subnet" {
  for_each      = local.gcp_producer_network_config.general_subnet
  name          = each.key
  ip_cidr_range = each.value.cidr
  region        = each.value.region
  network       = google_compute_network.producer_vpc.id

  # PSC NAT subnet requires PRIVATE_SERVICE_CONNECT purpose
  purpose = can(regex(".*psc-nat.*", each.key)) ? "PRIVATE_SERVICE_CONNECT" : null
}

resource "google_compute_subnetwork" "producer_proxy_subnet" {
  for_each      = local.gcp_producer_network_config.proxy_subnet
  name          = each.key
  ip_cidr_range = each.value.cidr
  region        = each.value.region
  network       = google_compute_network.producer_vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

#########################
# Firewall Rules (Producer VPC)
#########################
resource "google_compute_firewall" "producer_icmp" {
  name    = "${local.env}-${local.project}-producer-vpc-fw-allow-icmp-all"
  network = google_compute_network.producer_vpc.name

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "producer_ssh" {
  name    = "${local.env}-${local.project}-producer-vpc-fw-allow-ssh-iap"
  network = google_compute_network.producer_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "producer_http_health_check" {
  name      = "${local.env}-${local.project}-producer-vpc-fw-allow-http-health-check"
  direction = "INGRESS"
  network   = google_compute_network.producer_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["allow-health-check"]
}
