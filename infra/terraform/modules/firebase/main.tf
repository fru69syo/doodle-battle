# Firebase on top of the GCP project: the Firebase link, Firestore, Authentication (anonymous),
# the default Cloud Storage bucket, the Android/iOS apps and App Check.
#
# What is deliberately NOT here (the Firebase CLI owns it; see docs/LEARN_GCP.md §4):
#   - Firestore / Storage security rules, composite indexes and TTL policies (firebase/
#     firestore.rules, storage.rules, firestore.indexes.json) -> `firebase deploy --only firestore,storage`
#   - Cloud Functions -> `firebase deploy --only functions`
# One resource must have exactly one owner. If both Terraform and the Firebase CLI managed the
# rules, each deploy would silently undo the other.

resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.project_id
}

# Firestore in Native mode, Tokyo. The location can never be changed after creation.
resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # Optimistic concurrency + no App Engine coupling are the defaults recommended for new projects.
  concurrency_mode            = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"

  # Point-in-time recovery keeps 7 days of versions; it is billed as extra storage. Off by
  # default to stay in budget (the data that matters can be recreated by the children).
  point_in_time_recovery_enablement = var.firestore_pitr ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"

  # Protects against `terraform destroy` or a console click deleting all user data.
  delete_protection_state = var.deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy         = var.deletion_protection ? "ABANDON" : "DELETE"

  depends_on = [google_firebase_project.this]
}

# The TTL policy for replays/{id}.expireAt (30 days) is declared in firebase/firestore.indexes.json
# (fieldOverrides, "ttl": true) because the Firebase CLI owns index configuration.

# Firebase Authentication. The app only uses anonymous sign-in (no e-mail, no phone: children's
# data minimisation). Managing Auth from Terraform upgrades the project to "Firebase
# Authentication with Identity Platform". The upgrade cannot be undone; its no-cost tier (tens of
# thousands of monthly active users) is far above our scale. See docs/LEARN_GCP.md §8.
resource "google_identity_platform_config" "auth" {
  count   = var.manage_auth ? 1 : 0
  project = var.project_id

  # Never auto-delete anonymous users: the uid links a child to their online characters, and
  # deletion goes through deleteMyData (BACKEND.md §5).
  autodelete_anonymous_users = false

  sign_in {
    allow_duplicate_emails = false
    anonymous {
      enabled = true
    }
    email {
      enabled = false
    }
    phone_number {
      enabled = false
    }
  }

  depends_on = [google_firebase_project.this]
}

# Default Cloud Storage bucket for Firebase (snapshot images). Created in Tokyo.
resource "google_firebase_storage_default_bucket" "default" {
  count    = var.create_default_bucket ? 1 : 0
  provider = google-beta
  project  = var.project_id
  location = var.region

  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"

  depends_on = [google_firebase_project.this]
}

# --- Apps + App Check ---------------------------------------------------------------------------
# App Check proves that a request comes from our genuine app (Play Integrity on Android,
# App Attest on iOS). The realtime server and the Cloud Functions verify the token.

resource "google_firebase_android_app" "android" {
  count         = var.android_package_name == "" ? 0 : 1
  provider      = google-beta
  project       = var.project_id
  display_name  = "おえかきファイターズ Android"
  package_name  = var.android_package_name
  sha256_hashes = var.android_sha256_hashes

  # ABANDON in prod: removing the app from Terraform must not delete it (the shipped app's
  # config points at it).
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
  depends_on      = [google_firebase_project.this]
}

resource "google_firebase_apple_app" "ios" {
  count        = var.ios_bundle_id == "" ? 0 : 1
  provider     = google-beta
  project      = var.project_id
  display_name = "おえかきファイターズ iOS"
  bundle_id    = var.ios_bundle_id
  team_id      = var.ios_team_id == "" ? null : var.ios_team_id

  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
  depends_on      = [google_firebase_project.this]
}

resource "google_firebase_app_check_play_integrity_config" "android" {
  count     = length(google_firebase_android_app.android)
  project   = var.project_id
  app_id    = google_firebase_android_app.android[0].app_id
  token_ttl = "3600s"
}

resource "google_firebase_app_check_app_attest_config" "ios" {
  count     = length(google_firebase_apple_app.ios)
  project   = var.project_id
  app_id    = google_firebase_apple_app.ios[0].app_id
  token_ttl = "3600s"
}

# Enforcement for Firestore and Storage. Start with UNENFORCED, watch the App Check metrics in
# the Firebase console until (almost) all requests are verified, then switch to ENFORCED.
# Cloud Functions enforce App Check in code (`enforceAppCheck: true`), the battle server in its
# hello handshake.
resource "google_firebase_app_check_service_config" "services" {
  for_each         = toset(["firestore.googleapis.com", "firebasestorage.googleapis.com"])
  project          = var.project_id
  service_id       = each.value
  enforcement_mode = var.app_check_enforcement

  depends_on = [google_firebase_project.this]
}
