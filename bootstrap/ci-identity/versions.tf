terraform {
  required_version = ">= 1.9"

  # Same bucket as the cluster, its own prefix: this root outlives every
  # terraform destroy of the cluster.
  backend "gcs" {
    bucket = "rosy-precinct-477218-u8-tfstate"
    prefix = "ci-identity/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
