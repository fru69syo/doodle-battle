variable "project_id" {
  description = "GCP / Firebase project id."
  type        = string
}

variable "project_number" {
  description = "GCP project number (bootstrap output project_number)."
  type        = string
}

variable "region" {
  description = "Default region. asia-northeast1 = Tokyo."
  type        = string
  default     = "asia-northeast1"
}

variable "billing_account_id" {
  description = "Billing account id (XXXXXX-XXXXXX-XXXXXX) for the budget."
  type        = string
}

variable "monthly_budget_jpy" {
  description = "Monthly budget in yen for the dev project (counts against the owner's ¥5,000 total)."
  type        = number
  default     = 500
  validation {
    condition     = var.monthly_budget_jpy > 0 && var.monthly_budget_jpy <= 50000
    error_message = "monthly_budget_jpy must be between 1 and 50,000."
  }
}

variable "alert_email" {
  description = "E-mail for alerts and budget notifications."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to deploy through WIF."
  type        = string
  default     = "fru69syo/doodle-battle"
}

variable "wif_pool_name" {
  description = "Workload Identity Pool name (bootstrap output wif_pool_name)."
  type        = string
}

variable "realtime_min_instances" {
  description = "Minimum battle-server instances. 0 below ~3k DAU (docs/V2_INFRA.md §3.3)."
  type        = number
  default     = 0
}

variable "manage_auth" {
  description = "Manage anonymous Auth via Identity Platform (irreversible upgrade, see LEARN_GCP.md)."
  type        = bool
  default     = true
}

variable "create_default_bucket" {
  description = "Create the default Firebase Storage bucket (false if it already exists)."
  type        = bool
  default     = true
}

variable "android_package_name" {
  description = "Android application id (empty = do not manage the Android app)."
  type        = string
  default     = "com.fru69syo.doodle_battle"
}

variable "android_sha256_hashes" {
  description = "Play app signing + upload key SHA-256 fingerprints."
  type        = list(string)
  default     = []
}

variable "ios_bundle_id" {
  description = "iOS bundle id (empty = do not manage the iOS app)."
  type        = string
  default     = "com.fru69syo.doodleBattle"
}

variable "ios_team_id" {
  description = "Apple Developer Team ID."
  type        = string
  default     = ""
}

variable "app_check_enforcement" {
  description = "App Check enforcement for Firestore/Storage: start UNENFORCED, switch to ENFORCED when metrics look clean."
  type        = string
  default     = "UNENFORCED"
}

variable "require_app_check" {
  description = "Require App Check tokens at the battle server (dev builds use debug tokens)."
  type        = bool
  default     = false
}

variable "realtime_battle_engine" {
  description = "Battle engine of the realtime server: v3 or dev (see server/realtime/README.md)."
  type        = string
  default     = "dev"
}
