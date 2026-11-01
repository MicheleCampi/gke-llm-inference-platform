# External Secrets reads the Grafana Cloud secret as this GCP service account,
# through Workload Identity. Created by hand at first, imported into state on
# 1/11/2026; from here on Terraform owns them.
# The secret and its value stay outside Terraform: a value here would land in state.

locals {
  eso_sa_email = "eso-grafana-reader@${var.project_id}.iam.gserviceaccount.com"
  eso_ksa      = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/eso-grafana]"
  grafana_sec  = "projects/${var.project_id}/secrets/grafana-cloud-remote-write"
}

resource "google_service_account" "eso_grafana_reader" {
  project      = var.project_id
  account_id   = "eso-grafana-reader"
  display_name = "ESO reader for Grafana Cloud secret"
}

resource "google_secret_manager_secret_iam_member" "eso_reads_grafana" {
  project   = var.project_id
  secret_id = local.grafana_sec
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso_grafana_reader.email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso_grafana_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.eso_ksa

  # the workload pool PROJECT.svc.id.goog exists only once the cluster does
  depends_on = [module.gke_gpu]
}
