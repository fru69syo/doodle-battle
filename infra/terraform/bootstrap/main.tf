# Bootstrap: the few things that must exist before Terraform can run from GitHub Actions.
# Run ONCE per project by a human with Owner rights (Cloud Shell or a laptop with
# `gcloud auth application-default login`). See docs/LEARN_GCP.md §4.3.
#
#   1. APIs needed by Terraform itself
#   2. GCS bucket for remote Terraform state (versioned, private)
#   3. Service accounts for `terraform plan` (read-only) and `terraform apply`
#   4. Workload Identity Federation so GitHub Actions can use them without JSON keys

locals {
  bootstrap_services = [
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]

  plan_sa  = "tf-plan@${var.project_id}.iam.gserviceaccount.com"
  apply_sa = "tf-apply@${var.project_id}.iam.gserviceaccount.com"

  # Read-only roles: plan can see everything it manages, change nothing.
  plan_roles = [
    "roles/viewer",
    "roles/iam.securityReviewer",              # read IAM policies
    "roles/serviceusage.serviceUsageConsumer", # quota project for API calls
    "roles/secretmanager.viewer",              # secret metadata (never values)
    "roles/firebase.viewer",
  ]

  # Apply needs to create and change everything in envs/*. A curated list instead of Owner:
  # it cannot, for example, delete the project or change the billing account link.
  apply_roles = [
    "roles/artifactregistry.admin",
    "roles/cloudfunctions.viewer",
    "roles/datastore.owner",         # Firestore database + TTL fields
    "roles/firebase.admin",          # Firebase project link, apps, App Check, Auth
    "roles/iam.serviceAccountAdmin", # create service accounts, set their IAM
    "roles/iam.serviceAccountUser",  # deploy Cloud Run "as" the runtime account
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/identityplatform.admin",
    "roles/logging.configWriter", # log-based metrics
    "roles/monitoring.admin",     # alerts, uptime checks, dashboards
    "roles/pubsub.admin",
    "roles/resourcemanager.projectIamAdmin", # project-level role bindings
    "roles/run.admin",
    "roles/secretmanager.admin",            # secret containers + who may read them
    "roles/serviceusage.serviceUsageAdmin", # enable APIs
    "roles/storage.admin",
  ]
}

resource "google_project_service" "bootstrap" {
  for_each           = toset(local.bootstrap_services)
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {
  project_id = var.project_id
}

# --- Remote state bucket ------------------------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  # Every write creates a new object version: a broken state can be restored.
  versioning {
    enabled = true
  }

  # Keep only the last 20 noncurrent versions (state files are tiny).
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # State is the map of everything; never let `terraform destroy` remove it by accident.
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.bootstrap]
}

# --- Terraform service accounts -----------------------------------------------------------------
resource "google_service_account" "tf_plan" {
  account_id   = "tf-plan"
  display_name = "Terraform plan (read-only, GitHub Actions)"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_service_account" "tf_apply" {
  account_id   = "tf-apply"
  display_name = "Terraform apply (GitHub Actions, protected environment)"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "plan" {
  for_each = toset(local.plan_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.tf_plan.email}"
}

resource "google_project_iam_member" "apply" {
  for_each = toset(local.apply_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.tf_apply.email}"
}

# Both need to read/write the state (plan takes a lock, which is a small object in the bucket).
resource "google_storage_bucket_iam_member" "state_plan" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.tf_plan.email}"
}

resource "google_storage_bucket_iam_member" "state_apply" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.tf_apply.email}"
}

# Budgets live on the billing account, not in the project. These grants need a Billing Account
# Administrator to run bootstrap. Set grant_billing_roles = false and create them by hand if the
# person running bootstrap is not one.
resource "google_billing_account_iam_member" "apply_costs_manager" {
  count              = var.grant_billing_roles ? 1 : 0
  billing_account_id = var.billing_account_id
  role               = "roles/billing.costsManager"
  member             = "serviceAccount:${google_service_account.tf_apply.email}"
}

resource "google_billing_account_iam_member" "plan_viewer" {
  count              = var.grant_billing_roles ? 1 : 0
  billing_account_id = var.billing_account_id
  role               = "roles/billing.viewer"
  member             = "serviceAccount:${google_service_account.tf_plan.email}"
}

# --- Workload Identity Federation ---------------------------------------------------------------
module "github_wif" {
  source            = "../modules/github_wif"
  project_id        = var.project_id
  github_repository = var.github_repository

  environment_bindings = {
    (local.plan_sa)  = ["infra-${var.env}-plan"]
    (local.apply_sa) = ["infra-${var.env}"]
  }

  depends_on = [
    google_project_service.bootstrap,
    google_service_account.tf_plan,
    google_service_account.tf_apply,
  ]
}
