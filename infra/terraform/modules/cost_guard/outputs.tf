output "topic_id" {
  description = "Pub/Sub topic id for budget messages."
  value       = google_pubsub_topic.budget_alerts.id
}

output "budget_name" {
  description = "Budget resource name."
  value       = google_billing_budget.monthly.name
}
