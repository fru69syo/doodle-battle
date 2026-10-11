variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "project_number" {
  description = "GCP project number (budgets filter by number, not id)."
  type        = string
}

variable "env" {
  description = "Environment name (dev / prod), used in the budget display name."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account id, e.g. 012345-6789AB-CDEF01."
  type        = string
}

variable "monthly_budget" {
  description = "Monthly budget in whole units of currency_code."
  type        = number
}

variable "currency_code" {
  description = "Currency of the billing account (ISO 4217)."
  type        = string
  default     = "JPY"
}

variable "alert_thresholds" {
  description = "Actual-spend thresholds (1.0 = 100 %) that trigger e-mails. The kill switch uses its own thresholds on every message."
  type        = list(number)
  default     = [0.5, 0.8, 1.0]
}

variable "notification_channel_ids" {
  description = "Cloud Monitoring notification channels (e-mail) that receive budget alerts."
  type        = list(string)
  default     = []
}

variable "topic_name" {
  description = "Pub/Sub topic for budget messages. The function onBudgetAlert subscribes to it by name."
  type        = string
  default     = "budget-alerts"
}

variable "grant_billing_publisher" {
  description = "Grant the Cloud Billing budget service account publish rights on the topic."
  type        = bool
  default     = true
}
