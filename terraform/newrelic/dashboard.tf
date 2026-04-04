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
        query      = "SELECT latest(cpuPercent) as 'CPU %', latest(memoryUsageBytes)/1e6 as 'Memory MB', latest(state) as 'State' FROM ContainerSample WHERE hostname = 'ymatch-oci-arm' FACET containerName"
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

    widget_table {
      title  = "GitHub Actions Workflows"
      row    = 10
      column = 5
      width  = 8
      height = 3
      nrql_query {
        account_id = var.account_id
        query      = "SELECT latest(ghWorkflowName) as 'Workflow', latest(ghJobConclusion) as 'Result', latest(duration.ms)/1000 as 'Duration (s)' FROM Span WHERE otel.library.name = 'github-actions' FACET ghWorkflowName SINCE 7 days ago LIMIT 20"
      }
    }
  }
}
