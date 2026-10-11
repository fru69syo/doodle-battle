# Service accounts = identities for programs. Each program gets its own account with only the
# roles it needs ("least privilege"), so a bug or a leaked token in one place cannot touch the
# rest of the project.
#
#   battle-server        runtime identity of the Cloud Run realtime server
#   cost-guard           runtime identity of the kill-switch function (onBudgetAlert)
#   gha-realtime-deploy  GitHub Actions: push images + roll out new Cloud Run revisions
#   gha-firebase-deploy  GitHub Actions: `firebase deploy` (functions, rules, indexes)
#
# The Terraform plan/apply accounts are created by ../../bootstrap (they must exist before
# Terraform can run from CI).

locals {
  accounts = {
    battle_server = {
      id   = "battle-server"
      name = "Realtime battle server (Cloud Run)"
      roles = [
        "roles/datastore.user",          # read snapshots/users, write results (Firestore)
        "roles/logging.logWriter",       # structured logs
        "roles/monitoring.metricWriter", # custom metrics (if added later)
        "roles/cloudtrace.agent",        # traces
      ]
    }
    cost_guard = {
      id   = "cost-guard"
      name = "Kill switch: budget alert -> config/costMode"
      roles = [
        "roles/datastore.user", # write config/costMode
        "roles/logging.logWriter",
        "roles/eventarc.eventReceiver", # receive the Pub/Sub event through Eventarc
        "roles/run.invoker",            # Eventarc pushes to the function's Cloud Run service as this account
      ]
    }
    gha_realtime_deploy = {
      id   = "gha-realtime-deploy"
      name = "GitHub Actions: deploy realtime server"
      roles = [
        "roles/run.developer", # create revisions of existing services (cannot change IAM)
      ]
    }
    gha_firebase_deploy = {
      id   = "gha-firebase-deploy"
      name = "GitHub Actions: firebase deploy"
      roles = [
        "roles/cloudfunctions.admin",              # create/update functions, make callables public
        "roles/run.admin",                         # 2nd gen functions are Cloud Run services
        "roles/firebaserules.admin",               # Firestore / Storage rules
        "roles/datastore.indexAdmin",              # firestore.indexes.json
        "roles/cloudscheduler.admin",              # scheduled function (sweepMatches)
        "roles/eventarc.admin",                    # Firestore / Pub/Sub triggers
        "roles/pubsub.editor",                     # trigger subscriptions
        "roles/secretmanager.viewer",              # the CLI checks that referenced secrets exist
        "roles/serviceusage.serviceUsageConsumer", # the CLI checks enabled APIs
        "roles/firebase.viewer",                   # read the Firebase project config
        "roles/artifactregistry.reader",           # gcf-artifacts cleanup policy check
      ]
    }
  }

  project_bindings = merge([
    for key, sa in local.accounts : {
      for role in sa.roles : "${key}|${role}" => { key = key, role = role }
    }
  ]...)

  github_principal_prefix = "principal://iam.googleapis.com/${var.wif_pool_name}/subject/repo:${var.github_repository}:environment:"
}

resource "google_service_account" "this" {
  for_each     = local.accounts
  project      = var.project_id
  account_id   = each.value.id
  display_name = each.value.name
}

resource "google_project_iam_member" "this" {
  for_each = local.project_bindings
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.this[each.value.key].email}"
}

# --- Resource-level grants (narrower than project-level) ---------------------------------------

# The realtime deployer may push images only to our repository.
resource "google_artifact_registry_repository_iam_member" "realtime_push" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.this["gha_realtime_deploy"].email}"
}

# "Act as" permission: to deploy a service that runs as account X, the deployer must be allowed
# to use X. Without this, a deployer could run code as any (more powerful) account.
resource "google_service_account_iam_member" "realtime_act_as" {
  service_account_id = google_service_account.this["battle_server"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this["gha_realtime_deploy"].email}"
}

resource "google_service_account_iam_member" "firebase_act_as_cost_guard" {
  service_account_id = google_service_account.this["cost_guard"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this["gha_firebase_deploy"].email}"
}

# The other functions still run as the default compute service account (see LEARN_GCP.md §10).
resource "google_service_account_iam_member" "firebase_act_as_functions_runtime" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.functions_runtime_sa_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this["gha_firebase_deploy"].email}"
}

# --- Workload Identity Federation: which GitHub jobs may act as the deployers ------------------
# Only jobs that run in the named GitHub *environment* of our repository get a token. The
# environment can require a human approval, so nothing deploys without a reviewer.

resource "google_service_account_iam_member" "wif_realtime" {
  for_each           = toset(var.realtime_deploy_environments)
  service_account_id = google_service_account.this["gha_realtime_deploy"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.github_principal_prefix}${each.value}"
}

resource "google_service_account_iam_member" "wif_firebase" {
  for_each           = toset(var.firebase_deploy_environments)
  service_account_id = google_service_account.this["gha_firebase_deploy"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.github_principal_prefix}${each.value}"
}
