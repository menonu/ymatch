terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

# ---------------------------------------------------
# NOTE: GCP Cloud Run, Compute Engine VM, VPC, and
# Firewall resources have been removed.
# Production workloads now run on OCI (see terraform/oci/).
# GCP is used only for:
#   - Database backup storage (backup.tf)
#   - Budget monitoring (monitoring.tf)
# ---------------------------------------------------
