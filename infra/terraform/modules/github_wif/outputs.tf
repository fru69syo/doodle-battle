output "pool_name" {
  description = "Full pool name (projects/<number>/locations/global/workloadIdentityPools/<id>)."
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Full provider name; set it as the GitHub variable GCP_WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}
