output "repository_id" {
  description = "Repository id."
  value       = google_artifact_registry_repository.docker.repository_id
}

output "repository_name" {
  description = "Full resource name of the repository (used for IAM bindings)."
  value       = google_artifact_registry_repository.docker.name
}

output "docker_host" {
  description = "Docker registry host, e.g. asia-northeast1-docker.pkg.dev."
  value       = "${var.region}-docker.pkg.dev"
}

output "image_prefix" {
  description = "Prefix for image names: <host>/<project>/<repo>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
