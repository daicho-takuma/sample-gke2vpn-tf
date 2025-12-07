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
