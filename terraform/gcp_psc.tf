#########################
# Private Service Connect
#########################

# ----------------------
# Service Attachment (Producer VPC側)
# ----------------------
resource "google_compute_service_attachment" "psc_service_attachment" {
  name        = "${local.env}-${local.project}-psc-service-attachment"
  region      = local.gcp_producer_network_config.region
  description = "Service Attachment for PSC connection"

  enable_proxy_protocol = false
  connection_preference = "ACCEPT_AUTOMATIC" # 自動承認に変更
  nat_subnets           = [google_compute_subnetwork.producer_subnet["${local.env}-${local.project}-gcp-producer-psc-nat-subnet"].id]
  target_service        = google_compute_forwarding_rule.ilb["${local.env}-${local.project}-gcp-producer-ilb-proxy-subnet"].self_link

  domain_names = []
}

# ----------------------
# PSC Endpoint (Consumer VPC側)
# ----------------------
resource "google_compute_forwarding_rule" "psc_endpoint" {
  name                  = "${local.env}-${local.project}-psc-endpoint"
  region                = local.gcp_consumer_network_config.region
  network               = google_compute_network.consumer_vpc.name
  subnetwork            = google_compute_subnetwork.consumer_subnet["${local.env}-${local.project}-gcp-consumer-psc-endpoint-subnet"].id
  load_balancing_scheme = ""
  target                = google_compute_service_attachment.psc_service_attachment.self_link
  ip_address            = google_compute_address.psc_endpoint_ip.id
}

# ----------------------
# PSC Endpoint IP Address
# ----------------------
resource "google_compute_address" "psc_endpoint_ip" {
  name         = "${local.env}-${local.project}-psc-endpoint-ip"
  region       = local.gcp_consumer_network_config.region
  subnetwork   = google_compute_subnetwork.consumer_subnet["${local.env}-${local.project}-gcp-consumer-psc-endpoint-subnet"].id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
}
