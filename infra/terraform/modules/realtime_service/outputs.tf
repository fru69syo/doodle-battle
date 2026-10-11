output "service_name" {
  description = "Cloud Run service name."
  value       = google_cloud_run_v2_service.battle.name
}

output "uri" {
  description = "HTTPS URL of the service. The app connects to wss://<host>/v2."
  value       = google_cloud_run_v2_service.battle.uri
}

output "host" {
  description = "Host name of the service (used by the uptime check)."
  value       = trimprefix(google_cloud_run_v2_service.battle.uri, "https://")
}
