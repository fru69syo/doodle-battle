variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Repository location (same region as Cloud Run to avoid cross-region pulls)."
  type        = string
}

variable "repository_id" {
  description = "Repository name."
  type        = string
  default     = "containers"
}

variable "keep_recent" {
  description = "Always keep this many most recent image versions (rollback targets)."
  type        = number
  default     = 10
}

variable "delete_after_days" {
  description = "Delete images older than this many days (unless kept by keep_recent)."
  type        = number
  default     = 30
}
