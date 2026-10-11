# Production stack. Same modules as envs/dev with production settings:
# deletion protection on, App Check enforced (after the rollout check), budget ¥5,000.

locals {
  env                   = "prod"
  functions_runtime_sa  = "${var.project_number}-compute@developer.gserviceaccount.com"
  realtime_environments = ["realtime-${local.env}"]
  firebase_environments = ["firebase-${local.env}"]
}

module "services" {
  source     = "../../modules/project_services"
  project_id = var.project_id
}

module "firebase" {
  source                = "../../modules/firebase"
  project_id            = var.project_id
  region                = var.region
  deletion_protection   = true
  manage_auth           = var.manage_auth
  create_default_bucket = var.create_default_bucket
  android_package_name  = var.android_package_name
  android_sha256_hashes = var.android_sha256_hashes
  ios_bundle_id         = var.ios_bundle_id
  ios_team_id           = var.ios_team_id
  app_check_enforcement = var.app_check_enforcement

  depends_on = [module.services]
}

module "registry" {
  source     = "../../modules/artifact_registry"
  project_id = var.project_id
  region     = var.region

  depends_on = [module.services]
}

module "accounts" {
  source                       = "../../modules/service_accounts"
  project_id                   = var.project_id
  region                       = var.region
  artifact_repository_id       = module.registry.repository_id
  functions_runtime_sa_email   = local.functions_runtime_sa
  wif_pool_name                = var.wif_pool_name
  github_repository            = var.github_repository
  realtime_deploy_environments = local.realtime_environments
  firebase_deploy_environments = local.firebase_environments

  depends_on = [module.services]
}

module "secrets" {
  source     = "../../modules/secrets"
  project_id = var.project_id
  region     = var.region
  secrets = {
    # Used by judgeDrawing / registerCharacter (firebase/functions/src/config.ts). The value is
    # set by a human: `npx firebase functions:secrets:set ANTHROPIC_API_KEY`.
    ANTHROPIC_API_KEY = {
      description = "anthropic-api-key-for-cloud-functions"
      accessors   = ["serviceAccount:${local.functions_runtime_sa}"]
    }
  }

  depends_on = [module.services]
}

module "realtime" {
  source                = "../../modules/realtime_service"
  project_id            = var.project_id
  region                = var.region
  service_account_email = module.accounts.battle_server_email
  min_instances         = var.realtime_min_instances
  max_instances         = 1
  battle_engine         = var.realtime_battle_engine
  require_app_check     = true
  deletion_protection   = true

  depends_on = [module.services]
}

module "monitoring" {
  source                = "../../modules/monitoring"
  project_id            = var.project_id
  env                   = local.env
  alert_email           = var.alert_email
  realtime_service_name = module.realtime.service_name
  realtime_host         = module.realtime.host

  depends_on = [module.services]
}

module "cost_guard" {
  source                   = "../../modules/cost_guard"
  project_id               = var.project_id
  project_number           = var.project_number
  env                      = local.env
  billing_account_id       = var.billing_account_id
  monthly_budget           = var.monthly_budget_jpy
  currency_code            = "JPY"
  notification_channel_ids = [module.monitoring.notification_channel_id]

  depends_on = [module.services]
}
