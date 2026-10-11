variable "project_id" {
  description = "GCP project id (Firebase is added to this project)."
  type        = string
}

variable "region" {
  description = "Location for Firestore and the default Storage bucket."
  type        = string
}

variable "deletion_protection" {
  description = "Protect Firestore and the Storage bucket from deletion (true in prod)."
  type        = bool
}

variable "firestore_pitr" {
  description = "Enable Firestore point-in-time recovery (extra storage cost)."
  type        = bool
  default     = false
}

variable "manage_auth" {
  description = "Manage Firebase Auth (anonymous sign-in) with Terraform. Upgrades to Identity Platform (irreversible)."
  type        = bool
  default     = true
}

variable "create_default_bucket" {
  description = "Create the default Firebase Storage bucket. Set false if it was already created in the console."
  type        = bool
  default     = true
}

variable "android_package_name" {
  description = "Android application id. Empty string skips the Android app and its App Check config."
  type        = string
  default     = ""
}

variable "android_sha256_hashes" {
  description = "SHA-256 fingerprints of the signing certificates (Play app signing + upload key) for Play Integrity."
  type        = list(string)
  default     = []
}

variable "ios_bundle_id" {
  description = "iOS bundle id. Empty string skips the iOS app and its App Check config."
  type        = string
  default     = ""
}

variable "ios_team_id" {
  description = "Apple Developer Team ID (needed by App Attest)."
  type        = string
  default     = ""
}

variable "app_check_enforcement" {
  description = "App Check enforcement for Firestore and Storage: UNENFORCED or ENFORCED."
  type        = string
  default     = "UNENFORCED"
  validation {
    condition     = contains(["UNENFORCED", "ENFORCED"], var.app_check_enforcement)
    error_message = "app_check_enforcement must be UNENFORCED or ENFORCED."
  }
}
