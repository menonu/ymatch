# ---------------------------------------------------
# OCI Object Storage — production database backups
# Always Free: 20 GB object storage / 50k API requests/month
#
# Rotation (matches former GCS policy, issue #383):
#   daily/   → delete after 7 days
#   weekly/  → delete after 28 days
#   monthly/ → delete after 90 days
#
# Upload path: .github/workflows/db-backup.yml
#   oci os object put --namespace … --bucket-name ymatch-db-backups …
#
# DR note: this bucket is the off-VM recovery source. It lives in the same
# root as compute so `terraform destroy` without -target would plan to
# remove it. prevent_destroy blocks that; see docs/how_to/oci_deployment.md
# teardown section for the unlock procedure.
# ---------------------------------------------------

data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.tenancy_ocid
}

# Required so Object Storage can execute DELETE lifecycle rules on our behalf.
# Region identifier must match the provider region (e.g. ap-osaka-1).
# Scoped to the backup compartment + the permissions lifecycle needs (not
# tenancy-wide manage object-family). See:
# https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usinglifecyclepolicies.htm
resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-objectstorage-lifecycle"
  description    = "Allow Object Storage service to run lifecycle rules for db backups (#383)"
  statements = [
    join(" ", [
      "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid}",
      "where any {",
      "request.permission='BUCKET_INSPECT',",
      "request.permission='BUCKET_READ',",
      "request.permission='OBJECT_INSPECT',",
      "request.permission='OBJECT_UPDATE_TIER',",
      "request.permission='OBJECT_DELETE',",
      "request.permission='OBJECT_VERSION_DELETE'",
      "}",
    ]),
  ]
}

resource "oci_objectstorage_bucket" "db_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.tenancy.namespace
  name           = "ymatch-db-backups"
  access_type    = "NoPublicAccess"
  # STANDARD is Always Free eligible (shared 20 GB with other tiers)
  storage_tier = "Standard"
  versioning   = "Disabled"

  freeform_tags = {
    purpose     = "db-backup"
    environment = "production"
  }

  # Off-VM DR store — refuse accidental destroy with the rest of the stack.
  # To intentionally retire the bucket: remove this lifecycle block, apply,
  # download remaining objects, then destroy the bucket resource.
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object_lifecycle_policy" "db_backups" {
  namespace = data.oci_objectstorage_namespace.tenancy.namespace
  bucket    = oci_objectstorage_bucket.db_backups.name

  depends_on = [oci_identity_policy.objectstorage_lifecycle]

  rules {
    name        = "expire-daily"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 7
    time_unit   = "DAYS"
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["daily/"]
    }
  }

  rules {
    name        = "expire-weekly"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 28
    time_unit   = "DAYS"
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["weekly/"]
    }
  }

  rules {
    name        = "expire-monthly"
    action      = "DELETE"
    is_enabled  = true
    time_amount = 90
    time_unit   = "DAYS"
    target      = "objects"

    object_name_filter {
      inclusion_prefixes = ["monthly/"]
    }
  }
}

# ---------------------------------------------------
# Least-privilege principal for GitHub Actions uploads
# Issue a dedicated API key for this user (not the Terraform
# admin key) and set OCI_CLI_* secrets to that identity.
# ---------------------------------------------------

resource "oci_identity_user" "db_backup" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-db-backup"
  description    = "GitHub Actions identity for production DB backup uploads (#383)"
  # OCI Identity Domains require a primary email on user create.
  email          = var.db_backup_user_email

  freeform_tags = {
    purpose = "db-backup"
  }
}

resource "oci_identity_group" "db_backup" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-db-backup"
  description    = "Group for DB backup upload principal (#383)"
}

resource "oci_identity_user_group_membership" "db_backup" {
  user_id  = oci_identity_user.db_backup.id
  group_id = oci_identity_group.db_backup.id
}

resource "oci_identity_policy" "db_backup_upload" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-db-backup-upload"
  description    = "Least-privilege Object Storage access for DB backup CI (#383)"
  # Put + head only — no OBJECT_DELETE. Lifecycle expiry stays on the
  # Object Storage service principal (objectstorage_lifecycle above).
  statements = [
    "Allow group ${oci_identity_group.db_backup.name} to read buckets in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.db_backups.name}'",
    join(" ", [
      "Allow group ${oci_identity_group.db_backup.name} to manage objects in compartment id ${var.compartment_ocid}",
      "where all {",
      "target.bucket.name='${oci_objectstorage_bucket.db_backups.name}',",
      "any {",
      "request.permission='OBJECT_CREATE',",
      "request.permission='OBJECT_OVERWRITE',",
      "request.permission='OBJECT_INSPECT',",
      "request.permission='OBJECT_READ'",
      "}",
      "}",
    ]),
  ]
}
