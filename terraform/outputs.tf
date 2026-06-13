output "cluster_name" {
  description = "Nome del cluster GKE"
  value       = module.gke_gpu.cluster_name
}

output "cluster_location" {
  description = "Location del cluster"
  value       = module.gke_gpu.cluster_location
}

output "workload_identity_pool" {
  description = "Workload Identity pool"
  value       = module.gke_gpu.workload_identity_pool
}

output "gpu_node_pool_name" {
  description = "Nome del node pool GPU"
  value       = module.gke_gpu.gpu_node_pool_name
}

output "vpc_name" {
  description = "Nome della VPC dedicata"
  value       = google_compute_network.vpc.name
}

# Comando per ottenere il kubeconfig (usato in Fase 2).
output "get_credentials_command" {
  description = "Comando gcloud per il kubeconfig"
  value       = "gcloud container clusters get-credentials ${module.gke_gpu.cluster_name} --region ${module.gke_gpu.cluster_location} --project ${var.project_id}"
}
