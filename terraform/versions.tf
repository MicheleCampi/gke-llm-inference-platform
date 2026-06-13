terraform {
  required_version = ">= 1.9"

  backend "gcs" {
    bucket = "rosy-precinct-477218-u8-tfstate"
    prefix = "capstone/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
