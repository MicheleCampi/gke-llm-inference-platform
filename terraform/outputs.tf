output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke_gpu.cluster_name
}

output "cluster_location" {
  description = "Cluster location"
  value       = module.gke_gpu.cluster_location
}

output "workload_identity_pool" {
  description = "Workload Identity pool"
  value       = module.gke_gpu.workload_identity_pool
}

output "gpu_node_pool_name" {
  description = "GPU node pool name"
  value       = module.gke_gpu.gpu_node_pool_name
}

output "vpc_name" {
  description = "Dedicated VPC name"
  value       = google_compute_network.vpc.name
}

# Command that writes the kubeconfig for this cluster.
output "get_credentials_command" {
  description = "gcloud command for the kubeconfig"
  value       = "gcloud container clusters get-credentials ${module.gke_gpu.cluster_name} --region ${module.gke_gpu.cluster_location} --project ${var.project_id}"
}
