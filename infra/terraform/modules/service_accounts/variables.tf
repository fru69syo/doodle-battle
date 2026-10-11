variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Region of the Artifact Registry repository."
  type        = string
}

variable "artifact_repository_id" {
  description = "Artifact Registry repository the realtime deployer may push to."
  type        = string
}

variable "functions_runtime_sa_email" {
  description = "Runtime service account of the Firebase functions other than the kill switch (the default compute service account)."
  type        = string
}

variable "wif_pool_name" {
  description = "Full name of the Workload Identity Pool created by bootstrap: projects/<number>/locations/global/workloadIdentityPools/<id>."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository as owner/name."
  type        = string
}

variable "realtime_deploy_environments" {
  description = "GitHub environments whose jobs may deploy the realtime server."
  type        = list(string)
}

variable "firebase_deploy_environments" {
  description = "GitHub environments whose jobs may run firebase deploy."
  type        = list(string)
}
