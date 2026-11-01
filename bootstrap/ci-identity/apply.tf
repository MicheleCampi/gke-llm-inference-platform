# The identity the apply job runs as: separate from plan, no key, federated
# only for the terraform-apply environment (required reviewer, main only).
# Roles follow the resource types in terraform/; the first apply validates them.
resource "google_service_account" "apply" {
  account_id   = "terraform-apply-ci"
  display_name = "Terraform apply from GitHub Actions"
}

resource "google_service_account_iam_member" "apply_federation" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.github_apply_environment}"
}

# APIs, network, cluster and node pools, service accounts and their use.
resource "google_project_iam_member" "apply" {
  for_each = toset([
    "roles/compute.networkAdmin",
    "roles/container.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/serviceusage.serviceUsageAdmin",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.apply.email}"
}

# Project IAM admin, but it may grant or revoke only the one project role
# terraform/ grants (the node service account's): no path to escalate.
resource "google_project_iam_member" "apply_grants" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.apply.email}"

  condition {
    title      = "only-node-service-account-role"
    expression = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/container.defaultNodeServiceAccount'])"
  }
}

# The ESO binding on the Grafana secret, and the state: on those objects only.
resource "google_secret_manager_secret_iam_member" "apply_grafana" {
  project   = var.project_id
  secret_id = "grafana-cloud-remote-write"
  role      = "roles/secretmanager.admin"
  member    = "serviceAccount:${google_service_account.apply.email}"
}

resource "google_storage_bucket_iam_member" "apply_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.apply.email}"
}
