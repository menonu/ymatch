# ---------------------------------------------------
# Dashboard: ymatch Production Overview
# ---------------------------------------------------
resource "newrelic_one_dashboard" "production" {
  name        = "ymatch Production Overview"
  permissions = "public_read_write"

  # ---------------------------------------------------
  # Page 1: Infrastructure
  # ---------------------------------------------------
  page {
    name = "Infrastructure"

    # ── Row 1: Uptime Trend / CI·CD Status / Container Resources ──
    widget_line {
      title  = "Uptime Trend"
      row    = 1
      column = 1
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT percentage(count(*), WHERE result = 'SUCCESS') as 'Uptime %' FROM SyntheticCheck WHERE monitorName LIKE 'ymatch%' TIMESERIES AUTO SINCE 7 days ago"
      }
    }

    widget_billboard {
      title  = "CI / CD Status"
      row    = 1
      column = 5
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(conclusion) as 'Latest' FROM GitHubAction WHERE level = 'workflow' FACET workflow_name SINCE 7 days ago"
      }
    }

    widget_table {
      title  = "Container Resources"
      row    = 1
      column = 9
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(cpuPercent) as 'CPU %', latest(memoryUsageBytes)/1e6 as 'Mem MB' FROM ContainerSample WHERE hostname = '${var.nr_hostname}' FACET name"
      }
    }

    # ── Row 2: CPU / Memory / Disk ──
    widget_line {
      title  = "CPU Usage %"
      row    = 3
      column = 1
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(cpuPercent) FROM SystemSample WHERE hostname = '${var.nr_hostname}' TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Memory Usage %"
      row    = 3
      column = 5
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(memoryUsedPercent) FROM SystemSample WHERE hostname = '${var.nr_hostname}' TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "Disk Usage %"
      row    = 3
      column = 9
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT max(diskUsedPercent) as 'Disk Used %' FROM StorageSample WHERE hostname = '${var.nr_hostname}'"
      }
      warning  = 70
      critical = 80
    }

    # ── Row 3: Network / Error Logs / CI/CD Success Rate ──
    widget_line {
      title  = "Network I/O (bytes/sec)"
      row    = 5
      column = 1
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT average(receiveBytesPerSecond) as 'RX', average(transmitBytesPerSecond) as 'TX' FROM NetworkSample WHERE hostname = '${var.nr_hostname}' TIMESERIES AUTO"
      }
    }

    widget_line {
      title  = "Backend Error Logs"
      row    = 5
      column = 5
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT count(*) FROM Log WHERE service = 'backend' AND message LIKE '%ERROR%' TIMESERIES AUTO"
      }
    }

    widget_billboard {
      title  = "CI/CD Success Rate (30d)"
      row    = 5
      column = 9
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT percentage(count(*), WHERE conclusion = 'success') as 'Success %' FROM GitHubAction WHERE level = 'workflow' FACET workflow_name SINCE 30 days ago"
      }
      warning  = 90
      critical = 70
    }

    # ── Row 4: OCI Cost / Recent GHA Runs ──
    widget_billboard {
      title  = "OCI Monthly Cost (USD)"
      row    = 7
      column = 1
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(totalCostUSD) as 'OCI Cost $' FROM OCIBillingSample WHERE provider = 'OCI'"
      }
      warning  = 0.5
      critical = 1.0
    }

    widget_table {
      title  = "Recent GitHub Actions Runs"
      row    = 7
      column = 5
      width  = 8
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT workflow_name as 'Workflow', name as 'Job', conclusion as 'Result', duration_ms/1000 as 'Duration (s)', head_branch as 'Branch' FROM GitHubAction WHERE level = 'job' SINCE 30 days ago LIMIT 10"
      }
    }
  }

  # ---------------------------------------------------
  # Page 2: Database Backups
  # ---------------------------------------------------
  page {
    name = "Database Backups"

    # ── Row 1: Status / Hours Since / Size ──
    widget_billboard {
      title  = "Last Backup Status"
      row    = 1
      column = 1
      width  = 4
      height = 2
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
      height = 2
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
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(sizeBytes) / 1024 as 'Size (KB)' FROM DatabaseBackup WHERE status = 'success'"
      }
    }

    # ── Row 2: Recent Backups Table / Count ──
    widget_table {
      title  = "Recent Backups"
      row    = 3
      column = 1
      width  = 8
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT backupDate, status, daily, weekly, monthly, sizeBytes / 1024 as 'Size KB' FROM DatabaseBackup SINCE 30 days ago LIMIT 30"
      }
    }

    widget_billboard {
      title  = "Backups (Last 7 Days)"
      row    = 3
      column = 9
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT count(*) as 'Total', filter(count(*), WHERE status = 'success') as 'Success', filter(count(*), WHERE status != 'success') as 'Failed' FROM DatabaseBackup SINCE 7 days ago"
      }
    }

    # ── Row 3: Size Trend / Backups by Type ──
    widget_line {
      title  = "Backup Size Trend"
      row    = 5
      column = 1
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(sizeBytes) / 1024 as 'Size KB' FROM DatabaseBackup WHERE status = 'success' TIMESERIES 1 day SINCE 30 days ago"
      }
    }

    widget_bar {
      title  = "Backups by Type (30d)"
      row    = 5
      column = 5
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT filter(count(*), WHERE daily = 'true') as 'Daily', filter(count(*), WHERE weekly = 'true') as 'Weekly', filter(count(*), WHERE monthly = 'true') as 'Monthly' FROM DatabaseBackup WHERE status = 'success' SINCE 30 days ago"
      }
    }

    widget_billboard {
      title  = "Backup Success Rate"
      row    = 5
      column = 9
      width  = 4
      height = 2
      nrql_query {
        account_id = var.account_id
        query      = "SELECT percentage(count(*), WHERE status = 'success') as 'Success %' FROM DatabaseBackup SINCE 30 days ago"
      }
      warning  = 90
      critical = 70
    }
  }
}
