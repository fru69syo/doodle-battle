variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "extra_services" {
  description = "Additional APIs to enable (e.g. \"aiplatform.googleapis.com\")."
  type        = list(string)
  default     = []
}
