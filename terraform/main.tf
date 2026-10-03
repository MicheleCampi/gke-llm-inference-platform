provider "google" {
  project = var.project_id
  region  = var.region
}

# GCP APIs the cluster needs. Secret Manager is enabled out of band, with
# the resources that use it (README, Bootstrap).
# disable_on_destroy = false -> the APIs stay enabled on destroy (avoids
# dependency errors at teardown and leaves other workloads in the project alone).
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
  ])

  service = each.key

  disable_on_destroy         = false
  disable_dependent_services = false
}

# Dedicated VPC, not the default network. Regional routing.
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Primary subnet. GKE manages the secondary ranges (pods/services)
# through ip_allocation_policy in the module.
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

module "gke_gpu" {
  source = "./modules/gke-gpu"

  # The cluster is not created until the APIs are enabled.
  depends_on = [google_project_service.required]

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # GPU pool: scale-to-zero; a node exists only while a Pod requests a GPU.
  gpu_type           = var.gpu_type
  gpu_machine_type   = var.gpu_machine_type
  min_gpu_nodes      = var.min_gpu_nodes
  max_gpu_nodes      = var.max_gpu_nodes
  gpu_node_locations = var.gpu_node_locations
}
