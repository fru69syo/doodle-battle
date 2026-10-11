variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name shown in the dashboard title."
  type        = string
}

variable "alert_email" {
  description = "E-mail address that receives alerts and budget notifications."
  type        = string
}

variable "realtime_service_name" {
  description = "Cloud Run service name of the battle server."
  type        = string
}

variable "realtime_host" {
  description = "Host name of the battle server (for the uptime check)."
  type        = string
}

variable "error_log_threshold" {
  description = "Alert when more ERROR log entries than this appear within 10 minutes."
  type        = number
  default     = 10
}

variable "tick_lag_threshold_ms" {
  description = "Alert when the p95 of the per-minute worst tick lag exceeds this (ms)."
  type        = number
  default     = 80
}
