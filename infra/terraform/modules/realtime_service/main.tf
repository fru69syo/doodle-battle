# The realtime battle server on Cloud Run (docs/V2_INFRA.md §3.3, server/realtime/).
#
# Why these settings (details in docs/LEARN_GCP.md §5.3):
#   min 0 instances      -> scales to zero when nobody plays: no cost at night
#   max 1 instance       -> matchmaking queue and matches live in one process's memory, so both
#                           players of a match and any reconnect always reach the same process
#   session affinity     -> best-effort "same client -> same instance" (matters once max > 1)
#   request-based billing (cpu_idle = true) -> billed only while a WebSocket is open
#   timeout 15 min       -> a WebSocket is one long HTTP request; Cloud Run closes it at the
#                           timeout. The client reconnects transparently (resume token).

resource "google_cloud_run_v2_service" "battle" {
  project  = var.project_id
  name     = var.service_name
  location = var.region

  description = "おえかきファイターズ realtime battle server (WebSocket, 10 Hz ATB)"

  # Public endpoint: children's apps connect directly. Authentication happens inside the
  # protocol (Firebase ID token + App Check token in the first message), not through IAM.
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = true

  deletion_protection = var.deletion_protection

  template {
    service_account                  = var.service_account_email
    timeout                          = "${var.request_timeout_seconds}s"
    session_affinity                 = true
    max_instance_request_concurrency = var.max_concurrency
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    labels = {
      app       = "doodle-battle"
      component = "realtime"
    }

    containers {
      name  = "battle"
      image = var.initial_image

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true # request-based billing: CPU only while a request (socket) is open
        startup_cpu_boost = true # faster cold starts (hidden behind 「あいてを さがしているよ」)
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REQUIRE_APP_CHECK"
        value = var.require_app_check ? "true" : "false"
      }
      env {
        name  = "LOG_LEVEL"
        value = "info"
      }
      env {
        # "v3" = shared Engine v3 (production). "dev" = the simplified stand-in engine that ships
        # with the server until Engine v3 lands (never use it for rated play in prod).
        name  = "BATTLE_ENGINE"
        value = var.battle_engine
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 2
        failure_threshold = 15
        timeout_seconds   = 2
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 3
      }
    }
  }

  lifecycle {
    # CI (realtime-deploy.yml) rolls out new images with gcloud. Terraform owns every other
    # setting; ignoring the image here stops `terraform apply` from rolling back a deploy.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}
