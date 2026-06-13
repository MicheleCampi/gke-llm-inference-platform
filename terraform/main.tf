provider "google" {
  project = var.project_id
  region  = var.region
}

# VPC dedicata: niente default network. Routing regionale.
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnet primaria. I secondary range (pods/services) li gestisce GKE
# via ip_allocation_policy nel modulo.
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

module "gke_gpu" {
  source = "./modules/gke-gpu"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # GPU: scale-to-zero, acceso solo in Fase 3.
  gpu_type           = var.gpu_type
  gpu_machine_type   = var.gpu_machine_type
  min_gpu_nodes      = var.min_gpu_nodes
  max_gpu_nodes      = var.max_gpu_nodes
  gpu_node_locations = var.gpu_node_locations
}
