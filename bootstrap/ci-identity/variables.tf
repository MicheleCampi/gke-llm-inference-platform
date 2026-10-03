variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "state_bucket" {
  description = "Bucket holding the Terraform state the plan job reads"
  type        = string
}

variable "github_repository_id" {
  description = "Numeric ID of the GitHub repository allowed to run the plan (OIDC claim repository_id)"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric ID of the repository owner (OIDC claim repository_owner_id)"
  type        = string
}

variable "github_environment" {
  description = "GitHub environment the plan job must run in (OIDC claim environment)"
  type        = string
  default     = "terraform-plan"
}
