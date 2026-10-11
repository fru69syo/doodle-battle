output "state_bucket" {
  description = "GCS bucket for Terraform state. Pass it to `terraform init -backend-config=\"bucket=...\"` in envs/<env>."
  value       = google_storage_bucket.tfstate.name
}

output "project_number" {
  description = "Project number (needed by envs/<env> as project_number)."
  value       = data.google_project.this.number
}

output "wif_pool_name" {
  description = "Workload Identity Pool name (envs/<env> variable wif_pool_name)."
  value       = module.github_wif.pool_name
}

output "wif_provider_name" {
  description = "Set as GitHub environment variable GCP_WIF_PROVIDER."
  value       = module.github_wif.provider_name
}

output "tf_plan_sa" {
  description = "Set as GitHub variable GCP_TF_PLAN_SA (environment infra-<env>-plan)."
  value       = google_service_account.tf_plan.email
}

output "tf_apply_sa" {
  description = "Set as GitHub variable GCP_TF_APPLY_SA (environment infra-<env>)."
  value       = google_service_account.tf_apply.email
}
