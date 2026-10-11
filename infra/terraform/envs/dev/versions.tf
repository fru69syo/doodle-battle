terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.6"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.6"
    }
  }

  # Remote state in the bucket created by ../../bootstrap. The bucket name is passed at init:
  #   terraform init -backend-config="bucket=<project>-tfstate"
  # (backend blocks cannot use variables, so the bucket stays out of the code.)
  backend "gcs" {
    prefix = "envs/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  # Some APIs (budgets, Identity Platform) need an explicit quota project when called with
  # service-account or user credentials.
  user_project_override = true
  billing_project       = var.project_id
  default_labels = {
    app = "doodle-battle"
    env = "dev"
  }
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
  default_labels = {
    app = "doodle-battle"
    env = "dev"
  }
}
