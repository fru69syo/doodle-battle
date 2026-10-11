# Secret Manager "containers" for secrets. Terraform creates only the empty secret and decides
# who may read it. The VALUE is added by a human (gcloud / firebase CLI), so it never appears in
# Terraform code, plans or state. See docs/LEARN_GCP.md §5.6.

resource "google_secret_manager_secret" "this" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.key

  labels = {
    managed-by = "terraform"
  }

  annotations = {
    purpose = each.value.description
  }

  # Keep the secret's data in Tokyo only (data residency; one replica is also the cheapest).
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  # Destroyed versions stay recoverable for 7 days (protection against a mistaken rotation).
  version_destroy_ttl = "604800s"

  lifecycle {
    # The Firebase CLI adds its own labels when it sets a version; do not fight over them.
    ignore_changes = [labels]
  }
}

locals {
  accessors = merge([
    for id, s in var.secrets : {
      for m in s.accessors : "${id}|${m}" => { id = id, member = m }
    }
  ]...)
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = local.accessors
  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
