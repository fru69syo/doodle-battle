terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.6"
    }
    # A few Firebase resources (project link, apps, default Storage bucket) only exist in the
    # beta provider. The beta provider talks to the same APIs; it simply exposes newer fields.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.6"
    }
  }
}
