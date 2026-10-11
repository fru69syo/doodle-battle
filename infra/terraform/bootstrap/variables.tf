variable "project_id" {
  description = "GCP project id (create it first in the console or with gcloud)."
  type        = string
}

variable "env" {
  description = "Environment name: dev or prod. Determines the GitHub environment names (infra-<env>, infra-<env>-plan)."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "asia-northeast1"
}

variable "billing_account_id" {
  description = "Billing account id linked to the project (XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "grant_billing_roles" {
  description = "Grant the Terraform service accounts budget rights on the billing account (requires Billing Account Administrator)."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "GitHub repository allowed to use Workload Identity Federation, as owner/name."
  type        = string
  default     = "fru69syo/doodle-battle"
}
