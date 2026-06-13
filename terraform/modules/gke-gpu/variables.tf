variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster (es. europe-west4)"
  type        = string
}

variable "cluster_name" {
  description = "Nome del cluster GKE"
  type        = string
}

variable "network" {
  description = "Self-link o nome della VPC (creata dalla root, passata come input)"
  type        = string
}

variable "subnetwork" {
  description = "Self-link o nome della subnet"
  type        = string
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, STABLE"
  type        = string
  default     = "REGULAR"
}

variable "gpu_machine_type" {
  description = "Machine type per il node pool GPU (L4 richiede famiglia G2)"
  type        = string
  default     = "g2-standard-4"
}

variable "gpu_type" {
  description = "Tipo di acceleratore GPU"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_count" {
  description = "Numero di GPU per nodo"
  type        = number
  default     = 1
}

variable "gpu_driver_version" {
  description = "Versione driver gestita da GKE: DEFAULT, LATEST, INSTALLATION_DISABLED"
  type        = string
  default     = "DEFAULT"
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
  description = "Zone in cui confinare il node pool GPU (quota L4 per-zona)"
  type        = list(string)
  default     = ["europe-west4-a"]
}
