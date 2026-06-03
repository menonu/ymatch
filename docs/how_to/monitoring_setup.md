# Monitoring Setup Guide

## Overview

ymatch uses New Relic (Free tier) for application and infrastructure monitoring,
with Discord notifications for alerts. Cloud billing is monitored via native
OCI/GCP budget alerts.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    New Relic (Free Tier)                 │
│                                                         │
│  Infrastructure Agent ─── Host Metrics (CPU/Mem/Disk)   │
│         │                 Docker Container Stats         │
│         └── Log Forwarding (backend + caddy logs)       │
│                                                         │
│  Synthetic Monitors ──── API Health Ping (15 min)       │
│                          Frontend Ping (15 min)         │
│                                                         │
│  Alert Policy ────────── CPU > 85%                      │
│         │                Memory > 90%                   │
│         │                Disk > 80%                     │
│         │                Container down                 │
│         │                Synthetic failure              │
│         └── Discord Webhook notification                │
│                                                         │
│  Dashboard ──────────── Production Overview             │
│                          Database Backups               │
│                                                         │
│  GitHub Actions ──────── CI/CD Telemetry (via exporter) │
│                          DB Backup workflow → NR events  │
│                          Auto-deploy workflow → NR events│
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              Cloud Billing Alerts (native)               │
│                                                         │
│  OCI Budget ──── $1/month threshold, email alert        │
│  GCP Budget ──── $1/month threshold, email alert        │
└─────────────────────────────────────────────────────────┘
```

## New Relic Account

- **Tier**: Free (100 GB/month data ingest)
- **Region**: US (one.newrelic.com)
- **Account ID**: 7906787
- **Dashboard**: ymatch Production Overview

## Components

### 1. Infrastructure Agent (OCI VM)

The New Relic Infrastructure agent runs directly on the OCI VM (not in Docker)
to monitor host-level metrics and Docker containers.

**What it monitors:**
- Host CPU, memory, disk, network
- Docker container states and resource usage
- Log forwarding (backend + caddy containers)

**Setup / Reinstall:**
```bash
ssh -i ~/.ssh/oci_ymatch ubuntu@<VM_IP>
NEW_RELIC_LICENSE_KEY=<key> ./ymatch/scripts/setup_newrelic_agent.sh
```

**Agent management on the VM:**
```bash
sudo systemctl status newrelic-infra
sudo systemctl restart newrelic-infra
sudo journalctl -u newrelic-infra -f    # live logs
```

**Config files on the VM:**
| File | Purpose |
|------|---------|
| `/etc/newrelic-infra.yml` | License key and display name |
| `/etc/newrelic-infra/integrations.d/docker-config.yml` | Docker integration |
| `/etc/newrelic-infra/logging.d/docker-logs.yml` | Log forwarding |

### 2. Synthetic Monitors

Two ping monitors run from `AP_NORTHEAST_1` (Tokyo) every 15 minutes:

| Monitor | URL | Validates |
|---------|-----|-----------|
| ymatch API Health (OCI) | `https://<IP>.nip.io/api/v1/events` | JSON response |
| ymatch Frontend (OCI) | `https://<IP>.nip.io/` | HTTP 200 |

### 3. Alert Policy: ymatch OCI Production

| Condition | Threshold | Duration |
|-----------|-----------|----------|
| High CPU Usage | > 85% | 5 min |
| High Memory Usage | > 90% | 5 min |
| High Disk Usage | > 80% | 5 min |
| Docker Container Not Running | < 4 containers | 5 min |
| Synthetic Monitor Failure | ≥ 1 failure | 15 min |
| Database Backup Failed | Any failure event | Immediate |
| Database Backup Missing | No success event for 26h | Signal loss |

**Notification**: Discord webhook → `#alerts` channel

### 4. GitHub Actions Exporter

The `.github/workflows/newrelic-exporter.yml` workflow automatically sends
CI/CD telemetry to New Relic whenever any workflow completes. This appears
as distributed traces in New Relic.

**Required GitHub Secrets:**
| Secret | Description |
|--------|-------------|
| `NEW_RELIC_LICENSE_KEY` | Ingest license key (NRAL suffix) |
| `NEW_RELIC_ACCOUNT_ID` | New Relic account ID |

### 5. Database Backup Monitoring

The `.github/workflows/db-backup.yml` workflow runs daily at 03:00 JST and sends
`DatabaseBackup` custom events to New Relic with backup status, size, and type.

**Dashboard page**: "Database Backups" — shows backup status, size trends,
hours since last backup, and type breakdown (daily/weekly/monthly).

**Backup rotation** (via GCS lifecycle):
| Type | Frequency | Retained |
|------|-----------|----------|
| Daily | Every day | 7 |
| Weekly | Sunday | 4 |
| Monthly | 1st of month | 3 |

**GCS Bucket**: `tangential-map-491113-b4-db-backups` (us-west1)

### 6. Auto-Deploy Workflow

The `.github/workflows/deploy-oci.yml` deploys to OCI whenever CI passes on
`main`. Sends a `DeploymentEvent` to New Relic on completion.

### 7. Cloud Billing Alerts

#### OCI Budget
- **Name**: ymatch-always-free-guard
- **Threshold**: $1/month
- **Alert**: Email at 80% of threshold
- **Console**: OCI Console → Governance → Budgets

#### GCP Budget
- **Name**: ymatch-free-tier-guard
- **Threshold**: $1/month
- **Alert**: Email at 50%, 80%, 100% of threshold
- **Console**: GCP Console → Billing → Budgets & Alerts

## Data Ingest Estimate

| Source | Est. Monthly Volume |
|--------|-------------------|
| Infrastructure Agent (host metrics) | ~1-2 GB |
| Docker integration | ~0.5 GB |
| Log forwarding (backend + caddy) | ~2-5 GB |
| Synthetic monitors | ~0.1 GB |
| GitHub Actions exporter | ~0.01 GB |
| **Total** | **~4-8 GB** |

Free tier limit: 100 GB/month → well within budget.

## Useful NRQL Queries

```sql
-- CPU usage over time
SELECT average(cpuPercent) FROM SystemSample
WHERE hostname = 'ymatch-oci-arm' TIMESERIES AUTO

-- Memory usage
SELECT average(memoryUsedPercent) FROM SystemSample
WHERE hostname = 'ymatch-oci-arm' TIMESERIES AUTO

-- Docker container status
SELECT latest(state), latest(cpuPercent), latest(memoryUsageBytes)/1e6
FROM ContainerSample WHERE hostname = 'ymatch-oci-arm' FACET name

-- Backend error logs
SELECT count(*) FROM Log WHERE service = 'backend'
AND message LIKE '%ERROR%' TIMESERIES AUTO

-- Synthetic uptime percentage
SELECT percentage(count(*), WHERE result = 'SUCCESS')
FROM SyntheticCheck WHERE monitorName LIKE 'ymatch%' SINCE 7 days ago

-- GitHub Actions workflow duration
SELECT latest(duration.ms)/1000 FROM Span
WHERE otel.library.name = 'github-actions' FACET ghWorkflowName SINCE 30 days ago
```

## Troubleshooting

### Agent not sending data
```bash
# Check agent status
sudo systemctl status newrelic-infra

# Check logs for errors
sudo journalctl -u newrelic-infra --since "10 minutes ago" | grep -i error

# Verify license key
sudo cat /etc/newrelic-infra.yml
```

### Log forwarding not working
```bash
# Check log file permissions
sudo ls -la /var/lib/docker/containers/

# Verify container IDs match
docker inspect --format='{{.Id}}' ymatch_backend
sudo cat /etc/newrelic-infra/logging.d/docker-logs.yml
```

### After container restart (IDs change)
When containers are recreated, their IDs change. Re-run log config:
```bash
# On the VM, update log forwarding with new container IDs
BACKEND_ID=$(docker inspect --format='{{.Id}}' ymatch_backend)
CADDY_ID=$(docker inspect --format='{{.Id}}' ymatch_caddy)
DB_ID=$(docker inspect --format='{{.Id}}' ymatch_db)
# Then update /etc/newrelic-infra/logging.d/docker-logs.yml and restart agent
sudo systemctl restart newrelic-infra
```
