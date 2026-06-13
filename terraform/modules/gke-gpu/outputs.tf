output "cluster_name" {
  description = "Nome del cluster GKE"
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint del control plane"
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate del cluster (base64)"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location del cluster"
  value       = google_container_cluster.this.location
}

output "workload_identity_pool" {
  description = "Workload Identity pool del cluster"
  value       = "${var.project_id}.svc.id.goog"
}

output "gpu_node_pool_name" {
  description = "Nome del node pool GPU"
  value       = google_container_node_pool.gpu.name
}
