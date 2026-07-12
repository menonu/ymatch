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
# Database backups moved to OCI Object Storage (#383) —
# see terraform/oci/backup.tf. GCP remnants:
#   - backup.tf — DEPRECATED (GCS path retired; resources may
#     still exist if billing is restored for destroy only)
#   - monitoring.tf — optional budget alert
# ---------------------------------------------------
