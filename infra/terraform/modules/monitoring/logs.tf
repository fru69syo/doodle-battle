# Log-based metrics: turn structured log lines into time series that dashboards and alerts can use.
# The battle server and the functions write JSON logs with an `event` field (see
# server/realtime/src/log.ts and firebase/functions/src/cost/). Log-based metrics are free; only
# log ingestion above the free tier (50 GiB / month) costs money.

locals {
  battle_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.realtime_service_name}\""
}

resource "google_logging_metric" "match_ended" {
  project     = var.project_id
  name        = "realtime/match_ended"
  description = "Finished online matches, by mode (pvp/ghost) and end reason."
  filter      = "${local.battle_filter} AND jsonPayload.event=\"match_end\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Matches ended"
    labels {
      key         = "mode"
      description = "pvp or ghost"
    }
    labels {
      key         = "reason"
      description = "ko, timeout, forfeit, aborted"
    }
  }

  label_extractors = {
    mode   = "EXTRACT(jsonPayload.mode)"
    reason = "EXTRACT(jsonPayload.reason)"
  }
}

resource "google_logging_metric" "tick_lag" {
  project         = var.project_id
  name            = "realtime/tick_lag_ms"
  description     = "Worst lateness of the 10 Hz battle tick per minute (ms). High values = overloaded server."
  filter          = "${local.battle_filter} AND jsonPayload.event=\"stats\""
  value_extractor = "EXTRACT(jsonPayload.maxTickLagMs)"

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = "ms"
    display_name = "Battle tick lag"
  }

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 16
      growth_factor      = 2
      scale              = 1
    }
  }
}

resource "google_logging_metric" "auth_rejected" {
  project     = var.project_id
  name        = "realtime/auth_rejected"
  description = "Rejected WebSocket handshakes (bad ID token / App Check / consent), by reason."
  filter      = "${local.battle_filter} AND jsonPayload.event=\"auth_rejected\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key = "reason"
    }
  }

  label_extractors = {
    reason = "EXTRACT(jsonPayload.reason)"
  }
}

resource "google_logging_metric" "cost_mode_changed" {
  project     = var.project_id
  name        = "cost/mode_changed"
  description = "Kill switch changed config/costMode, by new mode."
  filter      = "jsonPayload.event=\"cost_mode_changed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key = "mode"
    }
  }

  label_extractors = {
    mode = "EXTRACT(jsonPayload.mode)"
  }
}

resource "google_logging_metric" "server_errors" {
  project     = var.project_id
  name        = "app/server_errors"
  description = "ERROR (or worse) log entries from Cloud Run services (battle server and 2nd gen functions)."
  filter      = "resource.type=\"cloud_run_revision\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key = "service"
    }
  }

  label_extractors = {
    service = "EXTRACT(resource.labels.service_name)"
  }
}
