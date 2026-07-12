# Deploying ymatch to Oracle Cloud Infrastructure (OCI) — Always Free Tier

This guide deploys the complete ymatch stack (Flutter web frontend, Rust/Axum backend, PostgreSQL) on OCI ARM Ampere A1 instances using the Always Free tier. Production and staging run on **separate VMs** (`ymatch-arm-v2` and `ymatch-arm-staging`) but use an **identical stack** — the same `docker-compose.oci.yml`, the same `Caddyfile.oci`, and the same container names — differing only by VM host and DB password. See issue #209 for the rationale.

## Architecture

```
Internet → Caddy (443/80, auto-SSL via nip.io)
               ├─ /api/*     → Backend (Rust/Axum, port 3000)
               ├─ /uploads/* → Backend (static files)
               └─ /*         → Frontend (Nginx, port 80)
                                    ↓
                              PostgreSQL (port 5432)
```

This stack runs identically on each VM:

| Environment | Instance | OCPUs / Memory | URL | Deploy workflow |
|-------------|----------|----------------|-----|-----------------|
| Production | `ymatch-arm-v2` | 2 / 12 GB | `https://<prod_ip>.nip.io` | `deploy-oci.yml` |
| Staging | `ymatch-arm-staging` | 1 / 4 GB | `https://<staging_ip>.nip.io` | `deploy-oci-staging.yml` |

## Cost Analysis (OCI Always Free Tier)

| Resource | Free Tier Limit | Our Usage | Status |
|----------|----------------|-----------|--------|
| A1 Flex ARM (OCPUs) | 4 OCPUs total | 3 OCPUs (prod 2 + staging 1) | ✅ FREE |
| A1 Flex ARM (Memory) | 24 GB total | 16 GB (prod 12 + staging 4) | ✅ FREE |
| Boot Volume | 200 GB total | 100 GB (50 GB × 2) | ✅ FREE |
| Object Storage | 20 GB total | DB backups (`ymatch-db-backups`) + tfstate | ✅ FREE |
| Public IPv4 | 2 included (no charge) | 2 IPs | ✅ FREE |
| Outbound Data | 10 TB/month | Minimal | ✅ FREE |
| VCN, Subnet, IGW | No charge | — | ✅ FREE |

> **Note**: OCI Always Free ARM resources are shared across your tenancy (4 OCPUs / 24 GB total across all A1 instances). The retired `ymatch-arm` (v1) instance was destroyed to make room for the staging VM. Adjust `instance_ocpus` / `instance_memory_gb` (production) and `staging_instance_ocpus` / `staging_instance_memory_gb` (staging) in Terraform variables, keeping the combined total within the free-tier limits.

## Prerequisites

1. **OCI Account**: [Sign up for Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
2. **OCI CLI**: Install and configure ([docs](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm))
3. **Terraform**: v1.5+ installed
4. **SSH Key Pair**: `ssh-keygen -t ed25519 -f ~/.ssh/oci_ymatch`
5. **OCIDs**: Gather the following from OCI Console:
   - **Tenancy OCID**: Profile → Tenancy → OCID
   - **User OCID**: Identity & Security → Users → Your user → OCID
   - **Compartment OCID**: Identity & Security → Compartments → OCID (or use tenancy OCID for root)
6. **API Key**: Profile → API Keys → Add API Key (note the fingerprint and download private key)

## Configuration

### 1. Configure OCI CLI

```bash
oci setup config
# Enter: tenancy OCID, user OCID, region, path to API private key
```

### 2. Create Terraform Variables

```bash
cd terraform/oci

cat > terraform.tfvars << 'EOF'
tenancy_ocid     = "ocid1.tenancy.oc1..xxxx"
user_ocid        = "ocid1.user.oc1..xxxx"
fingerprint      = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
private_key_path = "~/.oci/oci_api_key.pem"
region           = "ap-tokyo-1"
compartment_ocid = "ocid1.compartment.oc1..xxxx"
ssh_public_key   = "ssh-ed25519 AAAA..."
db_password      = "YourSecureDatabasePassword"

# Optional: Adjust instance size (defaults: 2 OCPUs, 12 GB)
# instance_ocpus      = 4
# instance_memory_gb  = 24
# boot_volume_size_gb = 100
EOF
```

> ⚠️ **Do not commit `terraform.tfvars`** — it contains sensitive credentials.

## Deployment

### Step 1: Provision Infrastructure

```bash
cd terraform/oci
terraform init
terraform plan
terraform apply
```

This creates: VCN, subnet, internet gateway, security list, A1 ARM instance.

Terraform will output the **public IP** and SSH command.

### Step 2: Wait for VM Setup

The cloud-init script installs Docker (~2-3 minutes). Check progress:

```bash
ssh -i ~/.ssh/oci_ymatch ubuntu@<PUBLIC_IP>
tail -f /var/log/ymatch-setup.log
# Wait for "ymatch OCI setup complete"
```

### Step 3: Deploy Application

On the VM:
```bash
./scripts/oci_deploy.sh <db_password> [public_ip]
```

Or from your local machine:
```bash
ssh -i ~/.ssh/oci_ymatch ubuntu@<PUBLIC_IP> \
  "cd ~/ymatch && ./scripts/oci_deploy.sh <db_password>"
```

The first build takes ~10-20 minutes (compiling Rust on ARM). Subsequent rebuilds are much faster thanks to Docker layer caching.

### Step 4: Verify

```bash
# Backend health
curl -s https://<PUBLIC_IP>.nip.io/api/v1/events

# Frontend
curl -s -o /dev/null -w "%{http_code}" https://<PUBLIC_IP>.nip.io/
```

## Redeployment (After Code Changes)

### Backend Only

On the VM:
```bash
cd ~/ymatch && ./scripts/oci_redeploy_backend.sh
```

### Frontend Only

On the VM:
```bash
cd ~/ymatch && ./scripts/oci_redeploy_frontend.sh
```

### Full Stack

On the VM:
```bash
cd ~/ymatch && git pull && \
  PUBLIC_IP=$(curl -sf http://checkip.amazonaws.com) \
  DB_PASSWORD=<password> \
  docker compose -f docker-compose.oci.yml up -d --build
```

## Management

### SSH Access
```bash
ssh -i ~/.ssh/oci_ymatch ubuntu@<PUBLIC_IP>
```

### View Logs
```bash
docker compose -f docker-compose.oci.yml logs -f           # All services
docker compose -f docker-compose.oci.yml logs -f backend    # Backend only
```

### Database Access
```bash
docker exec -it ymatch_db psql -U ymatch_user -d ymatch
```

### Service Status
```bash
docker compose -f docker-compose.oci.yml ps
```

### Restart Services
```bash
docker compose -f docker-compose.oci.yml restart backend
```

### Check Disk Usage
```bash
df -h /
docker system df
```

## GitHub Secrets Management

CI/CD workflows (`.github/workflows/deploy-oci.yml` for production and `deploy-oci-staging.yml` for staging) read several OCI-related values from GitHub Secrets. Production and staging now target **separate VMs**, so each has its own host and SSH-key secrets. You must update these whenever the underlying credential changes — most commonly when a VM is recreated and gets a new public IP.

### Secrets Reference

| Secret | Used by | When to update |
|--------|---------|----------------|
| `OCI_VM_HOST` | `deploy-oci.yml`, `db-backup.yml` (production) | **Every time the production VM's public IP changes** (recreates via Terraform) |
| `OCI_SSH_PRIVATE_KEY` | `deploy-oci.yml`, `db-backup.yml` (production) | When the production SSH key pair is rotated |
| `OCI_DB_PASSWORD` | `deploy-oci.yml` (production) | When the production database password changes |
| `OCI_STAGING_VM_HOST` | `deploy-oci-staging.yml` (staging) | **Every time the staging VM's public IP changes** (recreates via Terraform) |
| `OCI_STAGING_SSH_PRIVATE_KEY` | `deploy-oci-staging.yml` (staging) | When the staging SSH key pair is rotated |
| `OCI_STAGING_DB_PASSWORD` | `deploy-oci-staging.yml` (staging) | When the staging database password changes |
| `OCI_CLI_USER` | `db-backup.yml` | When the OCI API user for Object Storage upload changes |
| `OCI_CLI_TENANCY` | `db-backup.yml` | When the tenancy OCID changes (rare) |
| `OCI_CLI_FINGERPRINT` | `db-backup.yml` | When the OCI API key is rotated |
| `OCI_CLI_KEY_CONTENT` | `db-backup.yml` | When the OCI API private key is rotated (PEM body) |
| `OCI_CLI_REGION` | `db-backup.yml` | When the home region for Object Storage changes |
| `NEW_RELIC_LICENSE_KEY` | NR deployment / backup report | When the NR license is rotated |
| `NEW_RELIC_ACCOUNT_ID` | NR deployment / backup report | When the NR account changes |

> **Note:** `GCP_SA_KEY` is **retired** for backups (#383). Database dumps are uploaded to OCI Object Storage (`ymatch-db-backups`), not GCS.

The workflows also use the automatic `GITHUB_TOKEN` (not a secret) to clone the repo over HTTPS.

### Update Procedure

The simplest way is to set each secret individually with `gh secret set`. The recommended pattern uses a `.env` file to avoid leaking values in shell history:

```bash
# Create a throwaway file (do not commit it; add to .gitignore if reused)
cat > /tmp/oci-secrets.env <<'EOF'
OCI_VM_HOST=<redacted>
OCI_SSH_PRIVATE_KEY=/home/you/.ssh/oci_ymatch_v2
OCI_DB_PASSWORD=ymatch_oci_prod_2026
OCI_STAGING_VM_HOST=<redacted>
OCI_STAGING_SSH_PRIVATE_KEY=/home/you/.ssh/oci_ymatch_staging
OCI_STAGING_DB_PASSWORD=ymatch_oci_staging_2026
EOF

# Source the values into the current shell
set -a
source /tmp/oci-secrets.env
set +a

# Update each secret
gh auth status > /dev/null || { echo "Run 'gh auth login' first"; exit 1; }

gh secret set OCI_VM_HOST --body "$OCI_VM_HOST"
gh secret set OCI_SSH_PRIVATE_KEY < "$OCI_SSH_PRIVATE_KEY"
gh secret set OCI_DB_PASSWORD --body "$OCI_DB_PASSWORD"
gh secret set OCI_STAGING_VM_HOST --body "$OCI_STAGING_VM_HOST"
gh secret set OCI_STAGING_SSH_PRIVATE_KEY < "$OCI_STAGING_SSH_PRIVATE_KEY"
gh secret set OCI_STAGING_DB_PASSWORD --body "$OCI_STAGING_DB_PASSWORD"

# Clean up
shred -u /tmp/oci-secrets.env
```

For a **single-value update** (the most common case after a VM recreate):

```bash
# Just the new IP — only the relevant host secret changes in a typical recreate
gh secret set OCI_VM_HOST --body "<redacted>"          # production
gh secret set OCI_STAGING_VM_HOST --body "<redacted>"  # staging

# Verify (the value is not echoed, only the metadata)
gh secret list
```

### When a VM is Recreated

Terraform may assign a **different public IP** when an instance is destroyed and recreated (observed in issue #148). The new IP must be set in the matching host secret before the next CI run, otherwise workflows will fail with SSH connection errors.

```bash
# After terraform apply, get the new IPs
cd terraform/oci
terraform output instance_v2_public_ip            # production
terraform output instance_staging_public_ip       # staging

# Update the matching secret
gh secret set OCI_VM_HOST --body "<redacted>"          # production
gh secret set OCI_STAGING_VM_HOST --body "<redacted>"  # staging
```

The SSH key secrets do **not** need to change on a recreate if the Terraform `ssh_public_key_v2` / `ssh_public_key_staging` variables are unchanged — the new instance is provisioned with the same public key.

> **Future work**: A `scripts/update_oci_secrets.sh` helper was discussed (issue #139) but rejected in favor of documenting the manual procedure. The `gh secret set` invocation is short enough that a wrapper script adds little value, and the manual flow keeps the operation visible.

### When an SSH Key is Rotated

```bash
# 1. Generate new key
ssh-keygen -t ed25519 -C "ymatch-oci-v3" -f ~/.ssh/oci_ymatch_v3
# Save the public key to your password manager

# 2. Add the new public key to terraform.tfvars
#    (ssh_public_key_v2 = "ssh-ed25519 AAAA... ymatch-oci-v3")

# 3. Run terraform apply to add the new public key to the VM
cd terraform/oci
terraform apply

# 4. Update the GitHub secret
gh secret set OCI_SSH_PRIVATE_KEY < ~/.ssh/oci_ymatch_v3

# 5. Verify the new key works
ssh -i ~/.ssh/oci_ymatch_v3 ubuntu@$(terraform output -raw instance_v2_public_ip) "echo OK"

# 6. Remove the old public key from the VM (manual edit of ~/.ssh/authorized_keys)
```

### Security Notes

- **Never paste secrets in chat, emails, or unencrypted files.** `gh secret set` reads from a file (via shell redirection) or `--body` arg.
- **Do not log secret values.** Avoid `echo "$OCI_DB_PASSWORD"` in scripts; `set -x` is especially dangerous.
- **Audit regularly**: `gh secret list` shows all secrets and their last update time. Remove any you don't recognize.
- **Use `~/.netrc` or `gh auth login`** so `gh` works without re-authentication.

## Image Storage

On OCI, images use **local storage** (`IMAGE_STORAGE=local`):
- Stored in Docker volume `uploads`
- Served at `https://<IP>.nip.io/uploads/<uuid>.<ext>`
- Caddy proxies `/uploads/*` to the backend

This differs from the GCP deployment which uses Google Cloud Storage.

## Differences from GCP Deployment

| Aspect | GCP | OCI |
|--------|-----|-----|
| Backend | Cloud Run (serverless) | Docker on ARM VM |
| Frontend | Firebase Hosting (CDN) | Nginx on same VM |
| Database | Docker on e2-micro VM | Docker on same ARM VM |
| SSL | Managed by Cloud Run/Firebase | Caddy + Let's Encrypt (nip.io) |
| Image Storage | GCS bucket | Local Docker volume |
| DB backups | GCS (retired, #383) | Object Storage `ymatch-db-backups` |
| Auto-scaling | Yes (Cloud Run) | No (single VM) |
| Cost | Free tier (multiple services) | Free tier (VMs + Object Storage) |
| Public IP | Removed to save $3.60/mo | Included free |

## Teardown

```bash
cd terraform/oci
terraform destroy
```

This removes: VM, VCN, subnet, internet gateway, security list, and all associated resources.

> **Note**: The boot volume and its data will be destroyed. Back up the database first if needed
> (or restore from Object Storage — see [monitoring_setup.md](./monitoring_setup.md#5-database-backup-monitoring)):
> ```bash
> # One-off dump from the VM
> ssh ubuntu@<IP> "docker exec ymatch_db pg_dump -U ymatch_user ymatch" > backup.sql
>
> # Or pull the latest daily object from OCI Object Storage
> oci os object get -bn ymatch-db-backups --name daily/ymatch-YYYY-MM-DD.sql.gz --file backup.sql.gz
> ```

## Database backups (Object Storage)

Daily backups run via `.github/workflows/db-backup.yml`: SSH to production → `pg_dump | gzip` →
upload to bucket **`ymatch-db-backups`** (Terraform: `terraform/oci/backup.tf`). Lifecycle rules
delete `daily/` after 7 days, `weekly/` after 28 days, and `monthly/` after 90 days.

### One-time setup of OCI CLI secrets for the backup workflow

```bash
# Values from ~/.oci/config and the PEM private key used for Terraform/CLI
gh secret set OCI_CLI_USER --body "$(grep '^user=' ~/.oci/config | cut -d= -f2-)"
gh secret set OCI_CLI_TENANCY --body "$(grep '^tenancy=' ~/.oci/config | cut -d= -f2-)"
gh secret set OCI_CLI_FINGERPRINT --body "$(grep '^fingerprint=' ~/.oci/config | cut -d= -f2-)"
gh secret set OCI_CLI_REGION --body "$(grep '^region=' ~/.oci/config | cut -d= -f2-)"
gh secret set OCI_CLI_KEY_CONTENT < "$(grep '^key_file=' ~/.oci/config | cut -d= -f2- | sed "s|^~|$HOME|")"
```

After the first successful run, confirm objects with:

```bash
oci os object list --bucket-name ymatch-db-backups --all
```
