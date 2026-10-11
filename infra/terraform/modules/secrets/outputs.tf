output "secret_ids" {
  description = "Created secret ids."
  value       = sort(keys(google_secret_manager_secret.this))
}
