# ---------------------------------------------------
# Alert Policy
# ---------------------------------------------------
resource "newrelic_alert_policy" "oci_production" {
  name                = "ymatch OCI Production"
  incident_preference = "PER_CONDITION"
}

# ---------------------------------------------------
# NRQL Alert Conditions
# ---------------------------------------------------
resource "newrelic_nrql_alert_condition" "high_cpu" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "High CPU Usage (>85%)"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT average(cpuPercent) FROM SystemSample WHERE hostname = 'ymatch-oci-arm'"
  }

  critical {
    operator              = "above"
    threshold             = 85
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_nrql_alert_condition" "high_memory" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "High Memory Usage (>90%)"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT average(memoryUsedPercent) FROM SystemSample WHERE hostname = 'ymatch-oci-arm'"
  }

  critical {
    operator              = "above"
    threshold             = 90
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_nrql_alert_condition" "high_disk" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "High Disk Usage (>80%)"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT max(diskUsedPercent) FROM StorageSample WHERE hostname = 'ymatch-oci-arm'"
  }

  critical {
    operator              = "above"
    threshold             = 80
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_nrql_alert_condition" "container_down" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "Docker Container Not Running"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT uniqueCount(name) FROM ContainerSample WHERE hostname = 'ymatch-oci-arm'"
  }

  critical {
    operator              = "below"
    threshold             = 4
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_nrql_alert_condition" "synthetic_failure" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "Synthetic Monitor Failure"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT count(*) FROM SyntheticCheck WHERE result = 'FAILED' AND monitorName LIKE 'ymatch%'"
  }

  critical {
    operator              = "above_or_equals"
    threshold             = 1
    threshold_duration    = 900
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

# ---------------------------------------------------
# Backup Monitoring Alerts
# ---------------------------------------------------
resource "newrelic_nrql_alert_condition" "backup_failure" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "Database Backup Failed"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT count(*) FROM DatabaseBackup WHERE status != 'success'"
  }

  critical {
    operator              = "above_or_equals"
    threshold             = 1
    threshold_duration    = 60
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "backup_missing" {
  account_id = var.account_id
  policy_id  = newrelic_alert_policy.oci_production.id
  type       = "static"
  name       = "Database Backup Missing (>26h)"
  enabled    = true

  violation_time_limit_seconds = 86400

  nrql {
    query = "SELECT count(*) FROM DatabaseBackup WHERE status = 'success'"
  }

  # Alert fires when no successful backup event is received for 26 hours
  critical {
    operator              = "equals"
    threshold             = 0
    threshold_duration    = 3600
    threshold_occurrences = "ALL"
  }

  expiration_duration            = 93600
  open_violation_on_expiration   = true
  close_violations_on_expiration = false
}
