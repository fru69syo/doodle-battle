terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.6"
    }
  }
  # Bootstrap keeps its state locally (terraform.tfstate in this directory, git-ignored) because
  # it creates the bucket that will hold every other state. After the first apply you may move
  # it into that bucket: copy backend.tf.example to backend.tf and run
  # `terraform init -migrate-state -backend-config="bucket=<state bucket>"`.
}

provider "google" {
  project = var.project_id
  region  = var.region
  # Budgets / billing IAM are billed against this project's quota (needed for user credentials).
  user_project_override = true
  billing_project       = var.project_id
}
