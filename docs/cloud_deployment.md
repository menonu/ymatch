# Cloud Deployment Strategy

This document outlines the strategy for deploying the `ymatch` platform to the cloud, focusing on cost-efficiency using Free Tier services.

## Current Production Environment

| Component | Service | URL / Address |
|-----------|---------|---------------|
| Frontend | Firebase Hosting | https://ymatch-app.web.app |
| Backend API | Cloud Run (us-west1) | https://ymatch-backend-82867116789.us-west1.run.app |
| Database | e2-micro VM + Docker PostgreSQL | 10.0.0.2 (internal VPC) |
| Container Registry | Artifact Registry (us-central1) | us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo |

**GCP Project**: `tangential-map-491113-b4`

## Architecture

```
┌─────────────────┐     HTTPS      ┌──────────────────┐    VPC (10.0.0.0/24)    ┌──────────────────┐
│  Firebase        │◄──────────────►│  Cloud Run       │◄──────────────────────►│  e2-micro VM     │
│  Hosting         │                │  (ymatch-backend)│  Direct VPC Egress     │  PostgreSQL:5432 │
│  (Flutter Web)   │                │  Port 8080       │                        │  (Docker)        │
└─────────────────┘                └──────────────────┘                        └──────────────────┘
    ymatch-app.web.app                  Auto-scaling                               us-west1-b
```

- **Frontend → Backend**: The Flutter web app calls the Cloud Run backend URL directly (set at build time via `--dart-define=API_BASE_URL`).
- **Backend → DB**: Cloud Run uses **Direct VPC Egress** (no VPC connector needed) to reach the VM's internal IP on the same VPC subnet.
- **Firewall**: Only port 5432 from `10.0.0.0/24` is allowed to the DB VM. SSH (port 22) is open for admin access.

## Cost Analysis (GCP Free Tier)

| Resource | Free Tier Limit | Our Usage | Status |
|----------|----------------|-----------|--------|
| e2-micro VM (us-west1) | 1 instance, 744 hrs/month | 1 instance 24/7 | ✅ FREE |
| Standard PD (disk) | 30 GB/month | 30 GB (~3.2 GB used) | ✅ FREE |
| Cloud Run | 2M req, 360k GiB-sec, 180k vCPU-sec | Low usage | ✅ FREE |
| Firebase Hosting | 1 GB stored, 10 GB/month transfer | ~few MB | ✅ FREE |
| Artifact Registry | 0.5 GB storage | ~37 MB | ✅ FREE |
| VPC, Subnet, Firewall | No charge | — | ✅ FREE |
| **External IPv4 address** | **Not used (removed after setup)** | **None** | **✅ FREE** |
| Network Egress | 1 GB/month (premium tier) | Low usage | ✅ FREE |

### Why the VM has no external IP
The external IPv4 address costs ~$3.60/month and is only needed for initial setup (installing Docker, pulling images). After first boot, it is removed to stay within free tier.

- **SSH access**: Use IAP tunnel: `gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap`
- **If internet is needed temporarily** (e.g., Docker image update):
  ```bash
  # Add external IP
  gcloud compute instances add-access-config ymatch-db-vm --zone us-west1-b
  # ... do maintenance ...
  # Remove external IP
  gcloud compute instances delete-access-config ymatch-db-vm --zone us-west1-b --access-config-name external-nat
  ```

### Database Disk Budget
The 30 GB disk is shared between OS, Docker, and PostgreSQL data:
- OS + packages: ~2.5 GB
- Docker engine + images: ~0.4 GB
- **Available for PostgreSQL data: ~25 GB**
- Current DB size: ~8 MB

**Monitor disk usage** periodically:
```bash
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap --command "df -h / && docker exec postgres psql -U ymatch_user -d ymatch_db -c \"SELECT pg_size_pretty(pg_database_size('ymatch_db'));\""
```

## Prerequisites

- **gcloud CLI**: Authenticated with project access
- **Terraform**: v1.9+ installed
- **Docker**: For building backend images
- **Firebase CLI**: `npm install -g firebase-tools`
- **Flutter SDK**: For building the frontend

```bash
# Ensure gcloud is on PATH (in dev container)
export PATH="/home/ubuntu/google-cloud-sdk/bin:$PATH"

# Authenticate
gcloud auth login
gcloud auth application-default login
gcloud config set project tangential-map-491113-b4
```

## Full Deployment (First Time)

### 1. Build and Push Backend Image

```bash
cd /home/ubuntu/ws/ymatch

# Build for linux/amd64 (Cloud Run target)
docker build --platform linux/amd64 \
  -t us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest \
  -f backend.Dockerfile.prod .

# Push to Artifact Registry
docker push us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest
```

### 2. Apply Terraform Infrastructure

```bash
cd terraform

# Create terraform.tfvars (if not exists)
cat > terraform.tfvars << 'EOF'
project_id  = "tangential-map-491113-b4"
region      = "us-west1"
zone        = "us-west1-b"
db_password = "YOUR_SECURE_PASSWORD"
EOF

terraform init
terraform plan    # Review changes
terraform apply   # Create resources
```

This creates: VPC, subnet, firewall rules, e2-micro VM (with PostgreSQL), Cloud Run service, IAM policy.

### 3. Wait for DB VM Startup

The VM startup script installs Docker and pulls PostgreSQL. Wait ~2-3 minutes:

```bash
# Check startup completion
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap --command "docker ps"
# Should show postgres container running
```

### 4. Build and Deploy Frontend

```bash
cd frontend

# Build with production API URL
flutter build web \
  --dart-define=API_BASE_URL=https://ymatch-backend-xbtg3vdbmq-uw.a.run.app \
  --release

# Deploy to Firebase Hosting
cd ..
firebase deploy --only hosting --project tangential-map-491113-b4
```

### 5. Verify

```bash
# Backend health check
curl -s https://ymatch-backend-xbtg3vdbmq-uw.a.run.app/api/v1/events

# Frontend
curl -s -o /dev/null -w "%{http_code}" https://ymatch-app.web.app/
```

## Redeployment (After Code Changes)

### Backend Only

```bash
cd /home/ubuntu/ws/ymatch

# 1. Rebuild image
docker build --platform linux/amd64 \
  -t us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest \
  -f backend.Dockerfile.prod .

# 2. Push
docker push us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest

# 3. Deploy new revision to Cloud Run
gcloud run services update ymatch-backend \
  --region us-west1 \
  --image us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest \
  --project tangential-map-491113-b4
```

### Frontend Only

```bash
cd /home/ubuntu/ws/ymatch/frontend

# 1. Rebuild
flutter build web \
  --dart-define=API_BASE_URL=https://ymatch-backend-xbtg3vdbmq-uw.a.run.app \
  --release

# 2. Deploy
cd ..
firebase deploy --only hosting --project tangential-map-491113-b4
```

### Infrastructure Changes (Terraform)

```bash
cd terraform
terraform plan    # Review
terraform apply   # Apply
```

## Database Management

### SSH into DB VM
```bash
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap
```

### PostgreSQL Access on VM
```bash
docker exec -it postgres psql -U ymatch_user -d ymatch_db
```

### Check DB Size
```bash
docker exec postgres psql -U ymatch_user -d ymatch_db -c "
  SELECT pg_size_pretty(pg_database_size('ymatch_db')) AS db_size;
  SELECT schemaname||'.'||tablename AS table,
         pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
  FROM pg_tables WHERE schemaname='public'
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

### Check Disk Usage
```bash
df -h /
```

## Admin Account Management

Admin accounts are managed directly in the database. To promote a user to admin:

```bash
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap --command "
docker exec postgres psql -U ymatch_user -d ymatch_db -c \"UPDATE users SET role = 'admin' WHERE uuid = 'TARGET_UUID';\"
"
```

Current admin UUID: `625a6a92-9b70-488b-87b2-1bb68641f37e`

## Stop / Start (Cost Saving)

All resources are within free tier, but you can stop the VM when not in use.
Cloud Run auto-scales to zero (no action needed). Firebase Hosting is always on (static, free).

### GCP Console (Web UI)

| 操作 | 手順 |
|------|------|
| **VM停止** | [Compute Engine](https://console.cloud.google.com/compute/instances?project=tangential-map-491113-b4) → `ymatch-db-vm` → ⋮メニュー → **停止** |
| **VM起動** | 同上 → **開始/再開** |
| **Cloud Run確認** | [Cloud Run](https://console.cloud.google.com/run?project=tangential-map-491113-b4) → `ymatch-backend` → メトリクス・ログ確認 |
| **Firebase確認** | [Firebase Console](https://console.firebase.google.com/project/tangential-map-491113-b4/hosting) → Hosting → デプロイ履歴 |

> **Note**: VM停止中はCloud RunからDBに接続できずエラーが返ります。VMを再起動すればPostgreSQLがDocker restart policyで自動復旧し、Cloud Runも次のリクエストで再接続します。

### CLI: Stop
```bash
export PATH="/home/ubuntu/google-cloud-sdk/bin:$PATH"
gcloud compute instances stop ymatch-db-vm --zone us-west1-b --project tangential-map-491113-b4
```

### CLI: Start
```bash
export PATH="/home/ubuntu/google-cloud-sdk/bin:$PATH"
# 1. Start VM (PostgreSQL auto-starts via Docker --restart policy)
gcloud compute instances start ymatch-db-vm --zone us-west1-b --project tangential-map-491113-b4

# 2. Wait ~30s, then verify PostgreSQL is running
gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap --command "docker ps"

# 3. Cloud Run will reconnect automatically on next request
curl -s https://ymatch-backend-82867116789.us-west1.run.app/api/v1/events
```

### Status Check
```bash
# VM status
gcloud compute instances describe ymatch-db-vm --zone us-west1-b --format="get(status)" --project tangential-map-491113-b4

# Cloud Run (always "Active", scales to zero when idle)
gcloud run services describe ymatch-backend --region us-west1 --format="get(status.url)" --project tangential-map-491113-b4
```

## Teardown

```bash
cd terraform
terraform destroy   # Removes all GCP resources

# Firebase Hosting (manual)
firebase hosting:disable --project tangential-map-491113-b4
```

## Secondary Target: Oracle Cloud Infrastructure (OCI)

OCI offers an exceptionally generous "Always Free" tier that can serve as a fallback:

- **Compute**: Up to 4 ARM Ampere A1 instances (24 GB RAM total)
- **Compute**: 2 AMD-based VMs
- **Storage**: 200 GB Block Storage
- **Database**: Oracle Autonomous Database
- **No external IPv4 charge** (unlike GCP)

The Terraform configurations can be adapted to OCI by creating OCI-specific modules.
