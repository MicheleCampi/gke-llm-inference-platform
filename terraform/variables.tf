variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. europe-west4)"
  type        = string
  default     = "europe-west4"
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
  description = "GPU node pool zones"
  type        = list(string)
  default     = ["europe-west4-a"]
}
