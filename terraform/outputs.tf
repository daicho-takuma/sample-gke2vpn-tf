#########################
# Outputs
#########################

# Project ID
output "project_id" {
  description = "GCP Project ID"
  value       = local.project_id
}

# PSC Endpoint IP Address
output "psc_endpoint_ip" {
  description = "PSC Endpoint IP Address"
  value       = google_compute_address.psc_endpoint_ip.address
}

# GKE Cluster Name
output "gke_cluster_name" {
  description = "GKE Cluster Name"
  value       = google_container_cluster.gke.name
}

# GKE Cluster Location
output "gke_cluster_location" {
  description = "GKE Cluster Location"
  value       = google_container_cluster.gke.location
}

# Service Attachment Name
output "psc_service_attachment_name" {
  description = "PSC Service Attachment Name"
  value       = google_compute_service_attachment.psc_service_attachment.name
}
