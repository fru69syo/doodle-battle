output "notification_channel_id" {
  description = "E-mail notification channel id (also used by the budget)."
  value       = google_monitoring_notification_channel.email.id
}

output "dashboard_id" {
  description = "Dashboard resource id."
  value       = google_monitoring_dashboard.main.id
}

output "uptime_check_id" {
  description = "Uptime check id."
  value       = google_monitoring_uptime_check_config.battle.uptime_check_id
}
