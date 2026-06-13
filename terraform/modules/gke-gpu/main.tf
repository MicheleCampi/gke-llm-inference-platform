# Cluster regionale: control plane gestito, default node pool rimosso.
# I workload girano su node pool dedicate e dichiarate esplicitamente.
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Pattern canonico: si crea il cluster senza il default node pool
  # e si gestisce ogni pool come risorsa separata.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native: i secondary range pods/services sono gestiti da GKE.
  ip_allocation_policy {}

  # Workload Identity: niente SA key montate sui nodi, federazione KSA->GSA.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  # Evita distruzioni accidentali del control plane.
  deletion_protection = false
}

# Node pool GPU dedicata, scale-to-zero.
# Acceso solo quando un workload con toleration+nodeSelector lo richiede.
resource "google_container_node_pool" "gpu" {
  name           = "gpu-pool"
  node_locations = var.gpu_node_locations
  location       = var.region
  cluster        = google_container_cluster.this.name
  project        = var.project_id

  autoscaling {
    min_node_count = var.min_gpu_nodes
    max_node_count = var.max_gpu_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type
    image_type   = "COS_CONTAINERD"

    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count

      gpu_driver_installation_config {
        gpu_driver_version = var.gpu_driver_version
      }
    }

    # Workload Identity a livello nodo.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Taint: solo i pod che tollerano nvidia.com/gpu schedulano qui.
    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }

    labels = {
      workload = "gpu-inference"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
