# Docker repository for the realtime battle server image.
# Storage above 0.5 GB per month is billed, so cleanup policies delete old images automatically.
resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Container images for おえかきファイターズ servers"
  format        = "DOCKER"

  docker_config {
    # A tag (we use the git commit sha) always points to the same image: deploys are reproducible.
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_recent
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "${var.delete_after_days * 86400}s"
    }
  }
}
