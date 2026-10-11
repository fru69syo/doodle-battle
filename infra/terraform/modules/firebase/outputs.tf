output "firestore_database" {
  description = "Firestore database name."
  value       = google_firestore_database.default.name
}

output "storage_bucket" {
  description = "Default Firebase Storage bucket name (empty when not created by Terraform)."
  value       = length(google_firebase_storage_default_bucket.default) > 0 ? reverse(split("/", google_firebase_storage_default_bucket.default[0].bucket))[0] : ""
}

output "android_app_id" {
  description = "Firebase Android app id (empty when not managed)."
  value       = length(google_firebase_android_app.android) > 0 ? google_firebase_android_app.android[0].app_id : ""
}

output "ios_app_id" {
  description = "Firebase iOS app id (empty when not managed)."
  value       = length(google_firebase_apple_app.ios) > 0 ? google_firebase_apple_app.ios[0].app_id : ""
}
