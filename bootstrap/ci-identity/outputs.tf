output "workload_identity_provider" {
  description = "Value for the workload_identity_provider input of google-github-actions/auth"
  value       = google_iam_workload_identity_pool_provider.repo.name
}

output "service_account" {
  description = "Value for the service_account input of google-github-actions/auth"
  value       = google_service_account.plan.email
}
