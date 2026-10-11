output "battle_server_email" {
  description = "Runtime service account of the realtime server."
  value       = google_service_account.this["battle_server"].email
}

output "cost_guard_email" {
  description = "Runtime service account of the kill-switch function."
  value       = google_service_account.this["cost_guard"].email
}

output "realtime_deployer_email" {
  description = "Service account used by realtime-deploy.yml (GitHub variable GCP_DEPLOY_SA)."
  value       = google_service_account.this["gha_realtime_deploy"].email
}

output "firebase_deployer_email" {
  description = "Service account used by functions-deploy.yml (GitHub variable GCP_FIREBASE_DEPLOY_SA)."
  value       = google_service_account.this["gha_firebase_deploy"].email
}
