# Regional cluster: managed control plane, default node pool removed.
# Workloads run on dedicated, explicitly declared node pools.
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Canonical pattern: create the cluster without the default node pool
  # and manage each pool as a separate resource.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native: GKE manages the pods/services secondary ranges.
  ip_allocation_policy {}

  # Workload Identity: no service-account keys on the nodes; KSA->GSA federation.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  # Off on purpose: the lab is destroyed after each session, and with
  # deletion protection on, terraform destroy cannot delete the cluster.
  deletion_protection = false

  resource_labels = var.resource_labels

  # The control plane accepts connections only from the cluster's nodes and
  # from var.authorized_networks, empty by default. Operators pass their own
  # CIDR at apply time (README, Run it); no address is kept in the repository.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }
}

# Nodes run as a dedicated service account with the role GKE documents as
# the minimum for nodes, not as the Compute Engine default service account.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes of ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Dedicated GPU node pool, scale-to-zero. The autoscaler adds a node when a
# Pod requests nvidia.com/gpu; GKE's ExtendedResourceToleration admission
# controller adds the matching toleration, so no nodeSelector is needed.
resource "google_container_node_pool" "gpu" {
  name           = "gpu-pool"
  node_locations = var.gpu_node_locations
  location       = var.region
  cluster        = google_container_cluster.this.name
  project        = var.project_id

  # Nodes start only after their service account holds its role.
  depends_on = [google_project_iam_member.nodes]

  autoscaling {
    min_node_count = var.min_gpu_nodes
    max_node_count = var.max_gpu_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gpu_machine_type
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email

    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count

      gpu_driver_installation_config {
        gpu_driver_version = var.gpu_driver_version
      }
    }

    # Workload Identity on the node.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Taint: only Pods that tolerate nvidia.com/gpu are scheduled here.
    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }

    labels = {
      workload = "gpu-inference"
    }

    # The API sets this since GKE 1.12; declared so that Terraform never tries
    # to unset it (provider docs, node_config.metadata).
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

# CPU system pool: runs ArgoCD, the operator and the observability agent.
# No taint, so platform workloads schedule here.
resource "google_container_node_pool" "system" {
  name           = "system-pool"
  node_locations = var.system_node_locations
  location       = var.region
  cluster        = google_container_cluster.this.name
  project        = var.project_id

  # Nodes start only after their service account holds its role.
  depends_on = [google_project_iam_member.nodes]

  autoscaling {
    min_node_count = var.system_min_nodes
    max_node_count = var.system_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.system_machine_type
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      workload = "system"
    }

    # The API sets this since GKE 1.12; declared so that Terraform never tries
    # to unset it (provider docs, node_config.metadata).
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
