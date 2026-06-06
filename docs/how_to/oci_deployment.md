# Deploying ymatch to Oracle Cloud Infrastructure (OCI) — Always Free Tier

This guide deploys the complete ymatch stack (Flutter web frontend, Rust/Axum backend, PostgreSQL) on a single OCI ARM Ampere A1 instance using the Always Free tier.

## Architecture

```
Internet → Caddy (443/80, auto-SSL via nip.io)
               ├─ /api/*     → Backend (Rust/Axum, port 3000)
               ├─ /uploads/* → Backend (static files)
               └─ /*         → Frontend (Nginx, port 80)
                                    ↓
                              PostgreSQL (port 5432)
```

All services run as Docker containers on one `VM.Standard.A1.Flex` instance.

## Cost Analysis (OCI Always Free Tier)

| Resource | Free Tier Limit | Our Usage | Status |
|----------|----------------|-----------|--------|
| A1 Flex ARM (OCPUs) | 4 OCPUs total | 2 OCPUs | ✅ FREE |
| A1 Flex ARM (Memory) | 24 GB total | 12 GB | ✅ FREE |
| Boot Volume | 200 GB total | 50 GB | ✅ FREE |
| Public IPv4 | Included (no charge) | 1 IP | ✅ FREE |
| Outbound Data | 10 TB/month | Minimal | ✅ FREE |
| VCN, Subnet, IGW | No charge | — | ✅ FREE |

> **Note**: OCI Always Free ARM resources are shared across your tenancy. You can adjust `instance_ocpus` and `instance_memory_gb` in Terraform variables (up to 4 OCPUs / 24 GB total across all A1 instances).

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

CI/CD workflows (`.github/workflows/deploy-oci.yml` and `deploy-oci-staging.yml`) read several OCI-related values from GitHub Secrets. You must update these whenever the underlying credential changes — most commonly when the VM is recreated and gets a new public IP.

### Secrets Reference

| Secret | Used by | When to update |
|--------|---------|----------------|
| `OCI_VM_HOST` | All deploy workflows | **Every time the VM's public IP changes** (recreates via Terraform) |
| `OCI_SSH_PRIVATE_KEY` | All deploy workflows | When the SSH key pair used for VM access is rotated |
| `OCI_DB_PASSWORD` | `deploy-oci.yml` (production) and `deploy-oci-staging.yml` (validates compose) | When the production database password changes |
| `OCI_STAGING_DB_PASSWORD` | `deploy-oci-staging.yml` | When the staging database password changes |
| `GCP_SA_KEY` | (not OCI-specific; for billing backup) | When the GCP service account is rotated |
| `NEW_RELIC_LICENSE_KEY` | NR deployment report | When the NR license is rotated |
| `NEW_RELIC_ACCOUNT_ID` | NR deployment report | When the NR account changes |

The workflows also use the automatic `GITHUB_TOKEN` (not a secret) to clone the repo over HTTPS.

### Update Procedure

The simplest way is to set each secret individually with `gh secret set`. The recommended pattern uses a `.env` file to avoid leaking values in shell history:

```bash
# Create a throwaway file (do not commit it; add to .gitignore if reused)
cat > /tmp/oci-secrets.env <<'EOF'
OCI_VM_HOST=217.142.244.253
OCI_SSH_PRIVATE_KEY=/home/you/.ssh/oci_ymatch_v2
OCI_DB_PASSWORD=ymatch_oci_prod_2026
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
gh secret set OCI_STAGING_DB_PASSWORD --body "$OCI_STAGING_DB_PASSWORD"

# Clean up
shred -u /tmp/oci-secrets.env
```

For a **single-value update** (the most common case after a VM recreate):

```bash
# Just the new IP — only OCI_VM_HOST changes in a typical recreate
gh secret set OCI_VM_HOST --body "217.142.244.253"

# Verify (the value is not echoed, only the metadata)
gh secret list
```

### When a VM is Recreated

Terraform may assign a **different public IP** when an instance is destroyed and recreated (observed in issue #148). The new IP must be set in `OCI_VM_HOST` before the next CI run, otherwise workflows will fail with SSH connection errors.

```bash
# After terraform apply, get the new IP
cd terraform/oci
terraform output instance_v2_public_ip
# Output: "217.142.244.253"

# Update the secret
gh secret set OCI_VM_HOST --body "217.142.244.253"
```

The SSH key in `OCI_SSH_PRIVATE_KEY` does **not** need to change on a recreate if the Terraform `ssh_public_key_v2` variable is unchanged — the new instance is provisioned with the same public key.

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
| Auto-scaling | Yes (Cloud Run) | No (single VM) |
| Cost | Free tier (multiple services) | Free tier (single VM) |
| Public IP | Removed to save $3.60/mo | Included free |

## Teardown

```bash
cd terraform/oci
terraform destroy
```

This removes: VM, VCN, subnet, internet gateway, security list, and all associated resources.

> **Note**: The boot volume and its data will be destroyed. Back up the database first if needed:
> ```bash
> ssh ubuntu@<IP> "docker exec ymatch_db pg_dump -U ymatch_user ymatch" > backup.sql
> ```
