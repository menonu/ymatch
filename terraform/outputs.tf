output "backup_bucket_name" {
  value       = google_storage_bucket.db_backups.name
  description = "GCS bucket for database backups"
}

output "backup_service_account_email" {
  value       = google_service_account.backup.email
  description = "Service account for backup operations"
}
