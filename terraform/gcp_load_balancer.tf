#########################
# Regonal Internal Application Load Balancer
#########################

# ----------------------
# Applicaton Load Balancer
# ----------------------

resource "google_compute_address" "ilb" {
  for_each     = local.gcp_producer_network_config.proxy_subnet
  name         = "${local.env}-${local.project}-ilb-static-ip"
  subnetwork   = google_compute_subnetwork.producer_subnet["${local.env}-${local.project}-gcp-producer-ilb-frontend-subnet"].id
  address_type = "INTERNAL"
  region       = local.gcp_producer_network_config.region
}

// Forwading Rule
resource "google_compute_forwarding_rule" "ilb" {
  for_each              = local.gcp_producer_network_config.proxy_subnet
  name                  = "${local.env}-${local.project}-ilb-forwarding-rule"
  region                = local.gcp_producer_network_config.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.ilb.id
  ip_address            = google_compute_address.ilb[each.key].address
  network               = google_compute_network.producer_vpc.id
  subnetwork            = google_compute_subnetwork.producer_subnet["${local.env}-${local.project}-gcp-producer-ilb-frontend-subnet"].id
  network_tier          = "PREMIUM"
  depends_on            = [google_compute_subnetwork.producer_proxy_subnet]
}

// Target HTTP(S) Proxy
resource "google_compute_region_target_http_proxy" "ilb" {
  name    = "${local.env}-${local.project}-ilb-target-http-proxy"
  region  = local.gcp_producer_network_config.region
  url_map = google_compute_region_url_map.ilb.id
}

// URL Map
resource "google_compute_region_url_map" "ilb" {
  name            = "${local.env}-${local.project}-ilb-regional-url-map"
  region          = local.gcp_producer_network_config.region
  default_service = google_compute_region_backend_service.ilb.id
}

// Backend service
resource "google_compute_region_backend_service" "ilb" {
  name                  = "${local.env}-${local.project}-ilb-backend-service"
  region                = local.gcp_producer_network_config.region
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  enable_cdn            = false
  backend {
    balancing_mode        = "RATE"
    group                 = google_compute_network_endpoint_group.neg.self_link
    capacity_scaler       = 1.0
    max_rate_per_endpoint = 100
  }
  health_checks = [google_compute_region_health_check.ilb.id]
}

// Health Check
resource "google_compute_region_health_check" "ilb" {
  name   = "${local.env}-${local.project}-ilb-health-check-80"
  region = local.gcp_producer_network_config.region
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

// Hybrid Connectivity NEG
resource "google_compute_network_endpoint_group" "neg" {
  name                  = "${local.env}-${local.project}-ilb-neg"
  network               = google_compute_network.producer_vpc.id
  default_port          = "80"
  zone                  = local.gcp_zone
  network_endpoint_type = "NON_GCP_PRIVATE_IP_PORT"
}

resource "google_compute_network_endpoint" "neg" {
  for_each               = local.aws_instance_config.ec2_private
  network_endpoint_group = google_compute_network_endpoint_group.neg.name
  port                   = google_compute_network_endpoint_group.neg.default_port
  ip_address             = each.value.private_ip
  zone                   = local.gcp_zone
}
