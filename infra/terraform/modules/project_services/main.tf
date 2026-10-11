# Turns on the Google APIs this project uses. In GCP almost every product is an "API" that must
# be enabled per project before you can create resources in it. Enabling an API is free; you pay
# only for usage.
locals {
  default_services = [
    "artifactregistry.googleapis.com", # container images for Cloud Run
    "billingbudgets.googleapis.com",   # monthly budget + alerts
    "cloudbilling.googleapis.com",     # reading the billing account link
    "cloudbuild.googleapis.com",       # Cloud Functions builds (used by the Firebase CLI)
    "cloudfunctions.googleapis.com",   # Firebase Cloud Functions (2nd gen)
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com", # sweepMatches runs every minute
    "cloudtrace.googleapis.com",
    "eventarc.googleapis.com", # Firestore / Pub/Sub triggers for functions
    "firebase.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firebaserules.googleapis.com",
    "firebasestorage.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",  # short-lived tokens for Workload Identity Federation
    "identitytoolkit.googleapis.com", # Firebase Authentication
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com", # budget notifications -> kill switch
    "run.googleapis.com",    # Cloud Run (realtime battle server, functions)
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com", # Security Token Service (WIF token exchange)
  ]
  services = toset(concat(local.default_services, var.extra_services))
}

resource "google_project_service" "this" {
  for_each = local.services
  project  = var.project_id
  service  = each.value

  # Keep the API enabled when this resource is removed from code: disabling an API can delete
  # data or break resources created outside Terraform (for example by the Firebase CLI).
  disable_on_destroy         = false
  disable_dependent_services = false
}
