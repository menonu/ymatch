# ---------------------------------------------------
# DEPRECATED (#383) — GCS path retired.
# Active backups: terraform/oci/backup.tf (OCI Object Storage).
# Workflow: .github/workflows/db-backup.yml
#
# Do not apply this file for new environments. Resources below
# may remain in GCP state until billing is restored long enough
# to run `terraform destroy` / manual bucket delete.
#
# Historical rotation policy (mirrored on OCI):
#   daily/   → kept 7 days  (max 7)
#   weekly/  → kept 28 days (max 4)
#   monthly/ → kept 90 days (max 3)
# ---------------------------------------------------

resource "google_storage_bucket" "db_backups" {
  name          = "${var.project_id}-db-backups"
  location      = "US-WEST1"
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  # Daily backups: auto-delete after 7 days
  lifecycle_rule {
    condition {
      age                = 7
      matches_prefix     = ["daily/"]
    }
    action {
      type = "Delete"
    }
  }

  # Weekly backups: auto-delete after 28 days
  lifecycle_rule {
    condition {
      age                = 28
      matches_prefix     = ["weekly/"]
    }
    action {
      type = "Delete"
    }
  }

  # Monthly backups: auto-delete after 90 days
  lifecycle_rule {
    condition {
      age                = 90
      matches_prefix     = ["monthly/"]
    }
    action {
      type = "Delete"
    }
  }

  # Prevent accidental deletion of the bucket itself
  labels = {
    purpose     = "db-backup"
    environment = "production"
  }
}

# ---------------------------------------------------
# Service Account for backup operations
# ---------------------------------------------------

resource "google_service_account" "backup" {
  account_id   = "ymatch-db-backup"
  display_name = "ymatch DB Backup Service Account"
  description  = "Used by GitHub Actions to upload database backups to GCS"
}

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backup.email}"
}

# Service account key for GitHub Actions authentication
resource "google_service_account_key" "backup" {
  service_account_id = google_service_account.backup.name
}

output "backup_sa_key" {
  value       = google_service_account_key.backup.private_key
  description = "Base64-encoded service account key (set as GH secret GCP_SA_KEY)"
  sensitive   = true
}
