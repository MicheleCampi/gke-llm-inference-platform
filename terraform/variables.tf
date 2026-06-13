variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (es. europe-west4)"
  type        = string
  default     = "europe-west4"
}

variable "cluster_name" {
  description = "Nome base per cluster, VPC e subnet"
  type        = string
  default     = "capstone-inference"
}

variable "subnet_cidr" {
  description = "CIDR primario della subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "gpu_type" {
  description = "Tipo di acceleratore GPU"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_machine_type" {
  description = "Machine type GPU (L4 -> famiglia G2)"
  type        = string
  default     = "g2-standard-4"
}

variable "min_gpu_nodes" {
  description = "Min nodi GPU (0 = scale-to-zero)"
  type        = number
  default     = 0
}

variable "max_gpu_nodes" {
  description = "Max nodi GPU"
  type        = number
  default     = 1
}

variable "gpu_node_locations" {
  description = "Zone del node pool GPU"
  type        = list(string)
  default     = ["europe-west4-a"]
}
