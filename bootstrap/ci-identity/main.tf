provider "google" {
  project = var.project_id
}

# APIs the token exchange and a plan's refresh need: STS exchanges the GitHub
# OIDC token, IAM Credentials mints the service account's token, Cloud
# Resource Manager serves the project IAM policy that Terraform reads.
resource "google_project_service" "ci" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.ci]
}

# Admits a GitHub OIDC token only from this repository, by numeric IDs, and
# only from a job running in the protected environment, whose runs wait for
# a required reviewer's approval.
resource "google_iam_workload_identity_pool_provider" "repo" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "gke-llm-inference-platform"
  display_name                       = "gke-llm-inference-platform"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.environment"         = "assertion.environment"
  }

  attribute_condition = join(" && ", [
    "assertion.repository_id == '${var.github_repository_id}'",
    "assertion.repository_owner_id == '${var.github_owner_id}'",
    "assertion.environment == '${var.github_environment}'",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The identity the plan job runs as: read-only, no key.
resource "google_service_account" "plan" {
  account_id   = "terraform-plan-ci"
  display_name = "Terraform plan from GitHub Actions (read-only)"
}

resource "google_service_account_iam_member" "plan_federation" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github_repository_id}"
}

# Read access for a plan's refresh: network and subnet, cluster and node
# pools, service accounts, the project IAM policy.
resource "google_project_iam_member" "plan" {
  for_each = toset([
    "roles/browser",
    "roles/compute.networkViewer",
    "roles/container.clusterViewer",
    "roles/iam.serviceAccountViewer",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.plan.email}"

  # Project IAM is read and written through Cloud Resource Manager.
  depends_on = [google_project_service.ci]
}

# Read access to the state, on the state bucket only.
resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.plan.email}"
}
