#########################
# GKE Cluster (Autopilot with Private Nodes)
#########################
resource "google_container_cluster" "gke" {
  name     = local.gcp_gke_config.cluster_name
  location = local.gcp_gke_config.location

  # Enable Autopilot mode
  enable_autopilot = true

  network    = google_compute_network.consumer_vpc.name
  subnetwork = google_compute_subnetwork.consumer_subnet["${local.env}-${local.project}-gcp-consumer-gke-subnet"].name

  # Enable private cluster (private nodes)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # Enable IP aliasing (required for secondary ranges)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  deletion_protection = false
}
