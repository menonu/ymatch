# ---------------------------------------------------
# Dashboard: ymatch Production Overview
# ---------------------------------------------------
resource "newrelic_one_dashboard" "production" {
  name        = "ymatch Production Overview"
  permissions = "public_read_write"

  page {
    name = "Infrastructure"

    widget_line {
      title  = "CPU Usage %"
      row    = 1
      column = 1
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(cpuPercent) FROM SystemSample WHERE hostname = 'ymatch-oci-arm' TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Memory Usage %"
      row    = 1
      column = 5
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(memoryUsedPercent) FROM SystemSample WHERE hostname = 'ymatch-oci-arm' TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "Disk Usage %"
      row    = 1
      column = 9
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT max(diskUsedPercent) as 'Disk Used %' FROM StorageSample WHERE hostname = 'ymatch-oci-arm'"
      }
      warning  = 70
      critical = 80
    }

    widget_table {
      title  = "Docker Containers"
      row    = 4
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(cpuPercent) as 'CPU %', latest(memoryUsageBytes)/1e6 as 'Memory MB', latest(state) as 'State' FROM ContainerSample WHERE hostname = 'ymatch-oci-arm' FACET name"
      }
    }

    widget_line {
      title  = "Network I/O (bytes/sec)"
      row    = 4
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(receiveBytesPerSecond) as 'RX', average(transmitBytesPerSecond) as 'TX' FROM NetworkSample WHERE hostname = 'ymatch-oci-arm' TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Synthetic Monitor Uptime %"
      row    = 7
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT percentage(count(*), WHERE result = 'SUCCESS') as 'Uptime %' FROM SyntheticCheck WHERE monitorName LIKE 'ymatch%' TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Backend Error Logs"
      row    = 7
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT count(*) FROM Log WHERE service = 'backend' AND message LIKE '%ERROR%' TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "OCI Monthly Cost (USD)"
      row    = 10
      column = 1
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(totalCostUSD) as 'OCI Cost $' FROM OCIBillingSample WHERE provider = 'OCI'"
      }
      warning  = 0.5
      critical = 1.0
    }

    widget_billboard {
      title  = "GitHub Actions Latest Status"
      row    = 10
      column = 5
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(conclusion) as 'Latest' FROM Span WHERE workflow_name IS NOT NULL FACET workflow_name SINCE 7 days ago"
      }
    }

    widget_billboard {
      title  = "GitHub Actions Success Rate"
      row    = 10
      column = 9
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT percentage(count(*), WHERE conclusion = 'success') as 'Success %' FROM Span WHERE workflow_name IS NOT NULL FACET workflow_name SINCE 30 days ago"
      }
      warning  = 90
      critical = 70
    }

    widget_table {
      title  = "Recent GitHub Actions Runs"
      row    = 13
      column = 1
      width  = 12
      height = 4
      nrql_query {
        account_id = var.account_id
        query      = "SELECT workflow_name as 'Workflow', name as 'Job', conclusion as 'Result', duration.ms/1000 as 'Duration (s)', head_branch as 'Branch' FROM Span WHERE workflow_name IS NOT NULL SINCE 30 days ago LIMIT 10"
      }
    }
  }

  # ---------------------------------------------------
  # Page 2: Database Backups
  # ---------------------------------------------------
  page {
    name = "Database Backups"

    widget_billboard {
      title  = "Last Backup Status"
      row    = 1
      column = 1
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(status) as 'Status' FROM DatabaseBackup SINCE 7 days ago"
      }
    }

    widget_billboard {
      title  = "Hours Since Last Backup"
      row    = 1
      column = 5
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT (now() - latest(timestamp)) / 3600000 as 'Hours Ago' FROM DatabaseBackup WHERE status = 'success'"
      }
      warning  = 26
      critical = 50
    }

    widget_billboard {
      title  = "Last Backup Size"
      row    = 1
      column = 9
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(sizeBytes) / 1024 as 'Size (KB)' FROM DatabaseBackup WHERE status = 'success'"
      }
    }

    widget_table {
      title  = "Recent Backups"
      row    = 4
      column = 1
      width  = 8
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT backupDate, status, daily, weekly, monthly, sizeBytes / 1024 as 'Size KB' FROM DatabaseBackup SINCE 30 days ago LIMIT 30"
      }
    }

    widget_billboard {
      title  = "Backups (Last 7 Days)"
      row    = 4
      column = 9
      width  = 4
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT count(*) as 'Total', filter(count(*), WHERE status = 'success') as 'Success', filter(count(*), WHERE status != 'success') as 'Failed' FROM DatabaseBackup SINCE 7 days ago"
      }
    }

    widget_line {
      title  = "Backup Size Trend"
      row    = 7
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(sizeBytes) / 1024 as 'Size KB' FROM DatabaseBackup WHERE status = 'success' TIMESERIES 1 day SINCE 30 days ago"
      }
    }

    widget_bar {
      title  = "Backups by Type (Last 30 Days)"
      row    = 7
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT filter(count(*), WHERE daily = 'true') as 'Daily', filter(count(*), WHERE weekly = 'true') as 'Weekly', filter(count(*), WHERE monthly = 'true') as 'Monthly' FROM DatabaseBackup WHERE status = 'success' SINCE 30 days ago"
      }
    }
  }
}
