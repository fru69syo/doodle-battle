output "realtime_url" {
  description = "Battle server URL. The app connects to wss://<host>/v2 (REALTIME_PROTOCOL.md)."
  value       = module.realtime.uri
}

output "image_prefix" {
  description = "Docker image prefix for realtime-deploy.yml."
  value       = module.registry.image_prefix
}

output "realtime_deployer_sa" {
  description = "GitHub variable GCP_DEPLOY_SA in environment realtime-prod."
  value       = module.accounts.realtime_deployer_email
}

output "firebase_deployer_sa" {
  description = "GitHub variable GCP_FIREBASE_DEPLOY_SA in environment firebase-prod."
  value       = module.accounts.firebase_deployer_email
}

output "cost_guard_sa" {
  description = "Runtime account of onBudgetAlert (firebase/functions uses \"cost-guard@\")."
  value       = module.accounts.cost_guard_email
}

output "budget_topic" {
  description = "Pub/Sub topic that receives budget messages."
  value       = module.cost_guard.topic_id
}

output "storage_bucket" {
  description = "Default Firebase Storage bucket."
  value       = module.firebase.storage_bucket
}
