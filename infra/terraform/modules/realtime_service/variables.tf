variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Cloud Run region (asia-northeast1 = Tokyo, closest to the players)."
  type        = string
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "battle"
}

variable "service_account_email" {
  description = "Runtime service account."
  type        = string
}

variable "initial_image" {
  description = "Image used only when the service is first created; later deploys come from CI."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "min_instances" {
  description = "Minimum instances. 0 = scale to zero (cold start 1-3 s on the first connection)."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum instances. Must stay 1 while matchmaking is in-process (docs/V2_INFRA.md §3.3)."
  type        = number
  default     = 1
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3
    error_message = "max_instances must be between 1 and 3."
  }
}

variable "max_concurrency" {
  description = "Concurrent requests (= open WebSockets) per instance."
  type        = number
  default     = 250
}

variable "cpu" {
  description = "vCPU limit per instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance."
  type        = string
  default     = "512Mi"
}

variable "request_timeout_seconds" {
  description = "Maximum lifetime of one request (one WebSocket connection)."
  type        = number
  default     = 900
}

variable "require_app_check" {
  description = "Reject clients without a valid App Check token."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent terraform destroy from deleting the service."
  type        = bool
  default     = false
}

variable "battle_engine" {
  description = "Battle engine the server loads. v3 = the shared Engine v3. The dev stand-in is refused with NODE_ENV=production (always set here), so it is local-only."
  type        = string
  default     = "v3"
  validation {
    condition     = var.battle_engine == "v3"
    error_message = "battle_engine must be v3 (the dev stand-in engine only runs locally: npm run dev)."
  }
}
