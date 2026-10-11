# Cloud Monitoring: who gets told, what is checked from outside, what pages a human, and one
# dashboard. Everything here is inside the free allotment at our scale.

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Owner e-mail"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# Probes https://<battle-host>/healthz from three continents every 15 minutes. Waking the
# scaled-to-zero service for a few milliseconds costs (almost) nothing with request-based billing.
resource "google_monitoring_uptime_check_config" "battle" {
  project      = var.project_id
  display_name = "battle-server /healthz"
  timeout      = "10s"
  period       = "900s"

  selected_regions = ["ASIA_PACIFIC", "USA", "EUROPE"]

  http_check {
    path         = "/healthz"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.realtime_host
    }
  }

  content_matchers {
    content = "\"ok\":true"
    matcher = "CONTAINS_STRING"
  }
}

locals {
  channels = [google_monitoring_notification_channel.email.id]
  doc_link = "Runbook: docs/LEARN_GCP.md §9 (ログとメトリクスの見方) / §11 (よくある失敗)"
}

resource "google_monitoring_alert_policy" "uptime" {
  project               = var.project_id
  display_name          = "[battle] /healthz failing"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "Uptime check failed from 2+ regions"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.battle.uptime_check_id}\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "0s"
      aggregations {
        alignment_period     = "1800s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  documentation {
    content   = "The realtime server does not answer /healthz: online battles fail (single-player still works). Check the latest revision in Cloud Run and roll back if a deploy broke it. ${local.doc_link}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "battle_5xx" {
  project               = var.project_id
  display_name          = "[battle] 5xx ratio > 5 %"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "5xx / all requests"
    condition_threshold {
      filter             = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.realtime_service_name}\" AND metric.label.response_code_class=\"5xx\""
      denominator_filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.realtime_service_name}\""
      comparison         = "COMPARISON_GT"
      threshold_value    = 0.05
      duration           = "300s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  documentation {
    content   = "Many failing requests on the battle server. Check Logs Explorer: resource.labels.service_name=\"${var.realtime_service_name}\" severity>=ERROR. ${local.doc_link}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "server_errors" {
  project               = var.project_id
  display_name          = "[app] error logs > ${var.error_log_threshold} / 10 min"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "ERROR log entries (battle + functions)"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.server_errors.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_log_threshold
      duration        = "0s"
      aggregations {
        alignment_period     = "600s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.service"]
      }
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  documentation {
    content   = "Error logs are increasing. The `service` label tells which function or server. ${local.doc_link}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "tick_lag" {
  project               = var.project_id
  display_name          = "[battle] tick lag p95 > ${var.tick_lag_threshold_ms} ms"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "Battle loop is late (server overloaded?)"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.tick_lag.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.tick_lag_threshold_ms
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  documentation {
    content   = "The 10 Hz battle loop runs late, children see stutter. Consider cpu=2 or more instances (sharding). ${local.doc_link}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "judge_latency" {
  project               = var.project_id
  display_name          = "[functions] judgeDrawing p95 > 20 s"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "judgeDrawing latency"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"judgedrawing\""
      comparison      = "COMPARISON_GT"
      threshold_value = 20000
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"
    }
  }

  documentation {
    content   = "Cloud judging is slow; the app already falls back to on-device judging after its timeout. Check the AI provider status. ${local.doc_link}"
    mime_type = "text/markdown"
  }
}

# Log-based alert: fires on every matching log entry (rate-limited), no metric needed.
resource "google_monitoring_alert_policy" "cost_mode" {
  project               = var.project_id
  display_name          = "[cost] kill switch changed costMode"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "cost_mode_changed log entry"
    condition_matched_log {
      filter = "jsonPayload.event=\"cost_mode_changed\""
      label_extractors = {
        mode = "EXTRACT(jsonPayload.mode)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
    auto_close = "86400s"
  }

  documentation {
    content   = "config/costMode changed (see the `mode` label). saving = cloud judging off, ghosts sooner. minimal = also no PvP. Children do not see a message. To restore: raise the budget in Terraform or set config/costMode.pinned. docs/LEARN_GCP.md §6"
    mime_type = "text/markdown"
  }
}
