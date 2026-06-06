# ---------------------------------------------------
# OCI Budget Alert (Always Free guard)
# ---------------------------------------------------
resource "oci_budget_budget" "ymatch" {
  compartment_id = var.tenancy_ocid
  amount         = 1
  reset_period   = "MONTHLY"
  display_name   = "ymatch-always-free-guard"
  description    = "Alert if OCI spend exceeds free tier threshold"
  target_type    = "COMPARTMENT"
  targets        = [var.tenancy_ocid]
}

resource "oci_budget_alert_rule" "spend_alert" {
  budget_id      = oci_budget_budget.ymatch.id
  type           = "ACTUAL"
  threshold      = 80
  threshold_type = "PERCENTAGE"
  display_name   = "ymatch-spend-alert"
  recipients     = var.alert_email
  message        = "WARNING: OCI spend approaching free tier limit"
}

# ---------------------------------------------------
# Instance Principal for OCI Usage API access
# (allows NR Flex integration on VM to query billing)
# ---------------------------------------------------
resource "oci_identity_dynamic_group" "ymatch_instance" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-instance-group"
  description    = "Dynamic group for ymatch VM instance"
  matching_rule  = "instance.id = '${oci_core_instance.ymatch.id}'"
}

resource "oci_identity_policy" "ymatch_usage_read" {
  compartment_id = var.tenancy_ocid
  name           = "ymatch-usage-read"
  description    = "Allow ymatch VM to read usage reports for NR billing integration"
  statements = [
    "Allow dynamic-group ymatch-instance-group to read usage-report in tenancy",
  ]
}
