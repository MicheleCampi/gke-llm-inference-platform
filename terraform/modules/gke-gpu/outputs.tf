output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Control-plane endpoint"
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Cluster location"
  value       = google_container_cluster.this.location
}

output "workload_identity_pool" {
  description = "Cluster Workload Identity pool"
  value       = "${var.project_id}.svc.id.goog"
}

output "gpu_node_pool_name" {
  description = "GPU node pool name"
  value       = google_container_node_pool.gpu.name
}
