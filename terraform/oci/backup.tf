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
# ---------------------------------------------------

data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.tenancy_ocid
}

# Required so Object Storage can execute DELETE lifecycle rules on our behalf.
# Region identifier must match the provider region (e.g. ap-osaka-1).
# https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usinglifecyclepolicies.htm
resource "oci_identity_policy" "objectstorage_lifecycle" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-objectstorage-lifecycle"
  description    = "Allow Object Storage service to run lifecycle rules for db backups (#383)"
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in tenancy",
  ]
}

resource "oci_objectstorage_bucket" "db_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.tenancy.namespace
  name           = "ymatch-db-backups"
  access_type    = "NoPublicAccess"
  # STANDARD is Always Free eligible (shared 20 GB with other tiers)
  storage_tier   = "Standard"
  versioning     = "Disabled"

  freeform_tags = {
    purpose     = "db-backup"
    environment = "production"
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
