# Budget -> Pub/Sub -> kill switch (docs/LEARN_GCP.md §6).
#
#   Cloud Billing budget (¥5,000 / month)
#     ├─ e-mails at 50 / 80 / 100 % (actual) and 100 % (forecast)
#     └─ publishes the current spend to Pub/Sub topic `budget-alerts` several times a day
#           └─ Cloud Function `onBudgetAlert` (firebase/functions, runs as cost-guard)
#                 └─ writes config/costMode = normal | saving | minimal
#                       └─ functions, the battle server and the app read it and degrade quietly
#
# Note: billing data arrives with a delay of several hours, so the switch reacts late. That is
# why "saving" starts at 80 % and not at 100 %.

resource "google_pubsub_topic" "budget_alerts" {
  project = var.project_id
  name    = var.topic_name

  # Budget messages are only useful while fresh.
  message_retention_duration = "86400s"
}

# Cloud Billing publishes budget messages as this Google-owned service account.
resource "google_pubsub_topic_iam_member" "billing_publisher" {
  count   = var.grant_billing_publisher ? 1 : 0
  project = var.project_id
  topic   = google_pubsub_topic.budget_alerts.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:billing-budget-alert@system.gserviceaccount.com"
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account_id
  display_name    = "doodle-battle ${var.env} monthly"

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS" # free-tier credits lower the counted spend
  }

  amount {
    specified_amount {
      currency_code = var.currency_code # must equal the billing account currency
      units         = tostring(var.monthly_budget)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  # Forecast: "at this pace the month will end above 100 %" -> early warning.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    schema_version                   = "1.0"
    monitoring_notification_channels = var.notification_channel_ids
    # Keep the default e-mails to billing admins in addition to the channel above.
    disable_default_iam_recipients = false
  }

  depends_on = [google_pubsub_topic_iam_member.billing_publisher]
}
