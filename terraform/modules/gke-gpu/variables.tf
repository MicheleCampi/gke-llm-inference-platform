variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster (e.g. europe-west4)"
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "network" {
  description = "VPC self-link or name (created by the root module, passed in)"
  type        = string
}

variable "subnetwork" {
  description = "Subnet self-link or name"
  type        = string
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, STABLE"
  type        = string
  default     = "REGULAR"
}

variable "gpu_machine_type" {
  description = "Machine type for the GPU node pool (L4 requires the G2 family)"
  type        = string
  default     = "g2-standard-4"
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_count" {
  description = "GPUs per node"
  type        = number
  default     = 1
}

variable "gpu_driver_version" {
  description = "GKE-managed driver version: DEFAULT, LATEST, INSTALLATION_DISABLED"
  type        = string
  default     = "DEFAULT"
}

variable "min_gpu_nodes" {
  description = "Minimum GPU nodes (0 = scale-to-zero)"
  type        = number
  default     = 0
}

variable "max_gpu_nodes" {
  description = "Maximum GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_locations" {
  description = "Zones the GPU node pool is confined to"
  type        = list(string)
  default     = ["europe-west4-a"]
}

# --- System node pool (CPU): runs ArgoCD, the operator and Alloy. ---
variable "system_machine_type" {
  description = "Machine type for the CPU system node pool"
  type        = string
  default     = "e2-standard-2"
}
variable "system_min_nodes" {
  description = "Minimum system-pool nodes (per zone)"
  type        = number
  default     = 1
}
variable "system_max_nodes" {
  description = "Maximum system-pool nodes (per zone)"
  type        = number
  default     = 1
}
variable "system_node_locations" {
  description = "System-pool zones. One zone = 1 node (no HA, lowest cost)"
  type        = list(string)
  default     = ["europe-west4-a"]
}
