# One dashboard with the numbers the owner should glance at weekly.

locals {
  run_battle = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.realtime_service_name}\""

  tiles = [
    {
      title  = "Battle server: open connections / requests per s"
      filter = "metric.type=\"run.googleapis.com/request_count\" AND ${local.run_battle}"
      align  = "ALIGN_RATE"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.response_code_class"]
      plot   = "STACKED_BAR"
    },
    {
      title  = "Battle server: instances (0 = scaled to zero, no cost)"
      filter = "metric.type=\"run.googleapis.com/container/instance_count\" AND ${local.run_battle}"
      align  = "ALIGN_MAX"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.state"]
      plot   = "LINE"
    },
    {
      title  = "Battle server: billable instance time (s/s) = cost driver"
      filter = "metric.type=\"run.googleapis.com/container/billable_instance_time\" AND ${local.run_battle}"
      align  = "ALIGN_RATE"
      reduce = "REDUCE_SUM"
      group  = []
      plot   = "LINE"
    },
    {
      title  = "Battle server: CPU utilisation p95"
      filter = "metric.type=\"run.googleapis.com/container/cpu/utilizations\" AND ${local.run_battle}"
      align  = "ALIGN_PERCENTILE_95"
      reduce = "REDUCE_MAX"
      group  = []
      plot   = "LINE"
    },
    {
      title  = "Battle tick lag p95 (ms)"
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.tick_lag.name}\" AND resource.type=\"cloud_run_revision\""
      align  = "ALIGN_PERCENTILE_95"
      reduce = "REDUCE_MAX"
      group  = []
      plot   = "LINE"
    },
    {
      title  = "Matches ended (pvp vs ghost)"
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.match_ended.name}\" AND resource.type=\"cloud_run_revision\""
      align  = "ALIGN_DELTA"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.mode"]
      plot   = "STACKED_BAR"
    },
    {
      title  = "Functions: requests by function"
      filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name!=\"${var.realtime_service_name}\""
      align  = "ALIGN_RATE"
      reduce = "REDUCE_SUM"
      group  = ["resource.label.service_name"]
      plot   = "STACKED_AREA"
    },
    {
      title  = "judgeDrawing latency p95 (ms)"
      filter = "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"judgedrawing\""
      align  = "ALIGN_PERCENTILE_95"
      reduce = "REDUCE_MAX"
      group  = []
      plot   = "LINE"
    },
    {
      title  = "Firestore document reads / writes per s"
      filter = "metric.type=one_of(\"firestore.googleapis.com/document/read_ops_count\",\"firestore.googleapis.com/document/write_ops_count\") AND resource.type=\"firestore_instance\""
      align  = "ALIGN_RATE"
      reduce = "REDUCE_SUM"
      group  = ["metric.type"]
      plot   = "LINE"
    },
    {
      title  = "Error log entries by service"
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.server_errors.name}\" AND resource.type=\"cloud_run_revision\""
      align  = "ALIGN_DELTA"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.service"]
      plot   = "STACKED_BAR"
    },
    {
      title  = "Auth rejections at the battle server"
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.auth_rejected.name}\" AND resource.type=\"cloud_run_revision\""
      align  = "ALIGN_DELTA"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.reason"]
      plot   = "STACKED_BAR"
    },
    {
      title  = "Cost mode changes (kill switch)"
      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.cost_mode_changed.name}\""
      align  = "ALIGN_DELTA"
      reduce = "REDUCE_SUM"
      group  = ["metric.label.mode"]
      plot   = "STACKED_BAR"
    },
  ]

  dashboard = {
    displayName = "おえかきファイターズ ${var.env}"
    mosaicLayout = {
      columns = 12
      tiles = [
        for i, t in local.tiles : {
          xPos   = (i % 2) * 6
          yPos   = floor(i / 2) * 4
          width  = 6
          height = 4
          widget = {
            title = t.title
            xyChart = {
              dataSets = [{
                plotType = t.plot
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = t.filter
                    aggregation = merge(
                      {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = t.align
                        crossSeriesReducer = t.reduce
                      },
                      length(t.group) > 0 ? { groupByFields = t.group } : {}
                    )
                  }
                }
              }]
            }
          }
        }
      ]
    }
  }
}

resource "google_monitoring_dashboard" "main" {
  project        = var.project_id
  dashboard_json = jsonencode(local.dashboard)

  lifecycle {
    # The API adds defaults (e.g. empty fields) to the stored JSON; ignore that noise.
    ignore_changes = [dashboard_json]
  }
}
