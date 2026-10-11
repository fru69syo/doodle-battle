variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate, as owner/name."
  type        = string
}

variable "pool_id" {
  description = "Workload Identity Pool id."
  type        = string
  default     = "github"
}

variable "provider_id" {
  description = "Workload Identity Pool provider id."
  type        = string
  default     = "github-actions"
}

variable "environment_bindings" {
  description = "Map of service account email -> GitHub environment names whose jobs may impersonate it."
  type        = map(list(string))
  default     = {}
}
