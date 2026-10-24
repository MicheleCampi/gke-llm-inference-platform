variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. europe-west1)"
  type        = string
  default     = "europe-west1"
}

variable "cluster_name" {
  description = "Base name for the cluster, VPC and subnet"
  type        = string
  default     = "capstone-inference"
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR"
  type        = string
  default     = "10.0.0.0/20"
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_machine_type" {
  description = "GPU machine type (L4 -> G2 family)"
  type        = string
  default     = "g2-standard-4"
}

variable "min_gpu_nodes" {
  description = "Minimum GPU nodes across all zones (0 = scale-to-zero)"
  type        = number
  default     = 0
}

variable "max_gpu_nodes" {
  description = "Maximum GPU nodes across all zones"
  type        = number
  default     = 1
}

variable "gpu_node_locations" {
  description = "GPU node pool zones; the autoscaler picks one with capacity"
  type        = list(string)
  default     = ["europe-west1-b", "europe-west1-c"]
}

variable "authorized_networks" {
  description = "CIDRs that may reach the control plane besides the cluster's nodes. Set at apply time with TF_VAR_authorized_networks; empty: nodes only."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}
