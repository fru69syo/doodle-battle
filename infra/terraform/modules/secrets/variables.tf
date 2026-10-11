variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "The single replica location for secret data."
  type        = string
}

variable "secrets" {
  description = "Secrets to create: id -> { description, accessors (IAM members allowed to read the value) }."
  type = map(object({
    description = string
    accessors   = list(string)
  }))
}
