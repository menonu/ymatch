# ---------------------------------------------------
# DEPRECATED / RETIRED (#383)
#
# GCS backup resources (bucket, SA, SA key) have been removed from this
# configuration. Active backups: terraform/oci/backup.tf (OCI Object Storage).
# Workflow: .github/workflows/db-backup.yml
#
# If the root GCP Terraform *state* still tracks the old resources:
#   1. Restore billing on project tangential-map-491113-b4 (if needed)
#   2. `cd terraform && terraform destroy` (or targeted destroy) to drop
#      the GCS bucket + ymatch-db-backup SA/key
#   3. Remove the GitHub secret GCP_SA_KEY once nothing references it
#
# Do NOT run `terraform apply` on this root module for new environments —
# only destroy/cleanup of abandoned GCP resources.
# ---------------------------------------------------
