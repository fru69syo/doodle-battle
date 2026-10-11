# Workload Identity Federation (WIF) for GitHub Actions.
#
# Instead of storing a long-lived JSON key in GitHub (which can leak and never expires), each
# workflow run asks GitHub for a short-lived OIDC token ("I am job X of repo Y, environment Z"),
# and Google's Security Token Service exchanges it for a ~1 hour Google access token, but only if
# the token matches the rules below.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC tokens from GitHub Actions for ${var.github_repository}"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Copy claims from GitHub's token into Google attributes. `google.subject` is the identity
  # we bind roles to: "repo:OWNER/REPO:environment:NAME" for jobs that use an environment.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Hard gate: tokens from any other repository are rejected before any binding is checked.
  # (Every GitHub repository in the world can mint tokens for this issuer.)
  attribute_condition = "assertion.repository == \"${var.github_repository}\""
}

locals {
  principal_prefix = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_repository}:environment:"
  bindings = merge([
    for sa, envs in var.environment_bindings : {
      for env in envs : "${sa}|${env}" => { sa = sa, env = env }
    }
  ]...)
}

# Allow jobs of the given GitHub environments to impersonate the given service accounts.
resource "google_service_account_iam_member" "bindings" {
  for_each           = local.bindings
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.sa}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.principal_prefix}${each.value.env}"
}
