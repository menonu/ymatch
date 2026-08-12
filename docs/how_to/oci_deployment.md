# Deploying ymatch to Oracle Cloud Infrastructure (OCI) — Always Free Tier

This guide deploys the complete ymatch stack (Flutter web frontend, Rust/Axum backend, PostgreSQL) on OCI ARM Ampere A1 instances using the Always Free tier. Production and staging run on **separate VMs** (`ymatch-arm-v2` and `ymatch-arm-staging`) but use an **identical stack** — the same `docker-compose.oci.yml`, the same `Caddyfile.oci`, and the same container names — differing only by VM host and DB password. See issue #209 for the rationale.

## Architecture

```
Internet → Caddy (443/80, auto-SSL)
               │
               ├─ $OCI_DOMAIN / $OCI_DOMAIN_STAGING (primary FQDN)
               │     ├─ /api/*     → Backend (Rust/Axum, port 3000)
               │     ├─ /uploads/* → Backend (static files)
               │     └─ /*         → Frontend (Nginx, port 80)
               │
               └─ <ip>.nip.io (legacy) → session migrate page (#527) → $DOMAIN
                                    ↓
                              PostgreSQL (port 5432)
```

This stack runs identically on each VM. Public hostnames come from **GitHub Actions repository variables** (not hard-coded in workflows):

| Environment | Instance | OCPUs / Memory | Public FQDN (repo variable) | Deploy workflow |
|-------------|----------|----------------|-----------------------------|-----------------|
| Production | `ymatch-arm-v2` | 2 / 12 GB | `OCI_DOMAIN` | `deploy-oci.yml` |
| Staging | `ymatch-arm-staging` | 1 / 4 GB | `OCI_DOMAIN_STAGING` | `deploy-oci-staging.yml` |

Legacy `https://<ip>.nip.io` serves a **one-shot session migration page** (`caddy/migrate-session.html`, issue #527): it reads the guest UUID from the old origin’s `localStorage` and navigates to `https://$DOMAIN/?restore_uuid=…` so the Flutter app can call the existing restore path. Without a saved UUID it still lands on the new site welcome screen. After a soak period this can be simplified back to a permanent redirect only.

### Recovering a guest session after the DuckDNS cutover

| Situation | What to do |
|-----------|------------|
| Still have a bookmark/tab on `*.nip.io` | Open it once — the migrate page carries the guest UUID to DuckDNS automatically. |
| Already on DuckDNS, lost session | Welcome → **Restore Existing Account** with the master-key UUID (Profile). |
| UUID unknown, never saved | Start as a new guest (old data remains in DB but is not linked to this browser). |

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
# Backend health (primary hostname from repo variable OCI_DOMAIN)
curl -s "https://${OCI_DOMAIN}/api/v1/events"

# Frontend
curl -s -o /dev/null -w "%{http_code}" "https://${OCI_DOMAIN}/"

# Legacy nip.io still works and should 301 → $DOMAIN
curl -sI "https://<PUBLIC_IP>.nip.io/" | head -n1
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

> **Broader map:** local Terraform `.env`, GitHub Secrets, remote state,
> and future Vault are different stores — see
> [Secret Management](../explanation/secret_management.md) (#530).

CI/CD workflows (`.github/workflows/deploy-oci.yml` for production and `deploy-oci-staging.yml` for staging) read several OCI-related values from GitHub Secrets. Production and staging now target **separate VMs**, so each has its own host and SSH-key secrets. You must update these whenever the underlying credential changes — most commonly when a VM is recreated and gets a new public IP.

### Secrets Reference

| Name | Kind | Used by | When to update |
|------|------|---------|----------------|
| `OCI_VM_HOST` | secret | `deploy-oci.yml`, `db-backup.yml` (production) | **Every time the production VM's public IP changes** (recreates via Terraform). May be the raw IP or the same FQDN as `OCI_DOMAIN` once DNS is live. |
| `OCI_SSH_PRIVATE_KEY` | secret | `deploy-oci.yml`, `db-backup.yml` (production) | When the production SSH key pair is rotated |
| `OCI_DB_PASSWORD` | secret | `deploy-oci.yml` (production) | When the production database password changes |
| `OCI_STAGING_VM_HOST` | secret | `deploy-oci-staging.yml` (staging) | **Every time the staging VM's public IP changes**. May be IP or the same FQDN as `OCI_DOMAIN_STAGING`. |
| `OCI_STAGING_SSH_PRIVATE_KEY` | secret | `deploy-oci-staging.yml` (staging) | When the staging SSH key pair is rotated |
| `OCI_STAGING_DB_PASSWORD` | secret | `deploy-oci-staging.yml` (staging) | When the staging database password changes |
| `VAPID_PUBLIC_KEY_STAGING` | secret | `deploy-oci-staging.yml` → host `VAPID_PUBLIC_KEY` | When staging Web Push application-server keys rotate (#179) |
| `VAPID_PRIVATE_KEY_STAGING` | secret | `deploy-oci-staging.yml` → host `VAPID_PRIVATE_KEY` | Same pair as public; **server-only** |
| `VAPID_SUBJECT_STAGING` | secret | `deploy-oci-staging.yml` → host `VAPID_SUBJECT` | Contact URI (`mailto:` or `https:`); optional but recommended |
| `DUCKDNS_TOKEN` | secret | `deploy-oci.yml`, `deploy-oci-staging.yml` | When the DuckDNS account token is rotated (issue #523) |
| `OCI_DOMAIN` | **variable** | `deploy-oci.yml` | When the production public FQDN changes (e.g. `app.example.duckdns.org`) |
| `OCI_DOMAIN_STAGING` | **variable** | `deploy-oci-staging.yml` | When the staging public FQDN changes |
| `OCI_CLI_USER` | `db-backup.yml` | When the least-privilege `ymatch-db-backup` user changes |
| `OCI_CLI_TENANCY` | `db-backup.yml` | When the tenancy OCID changes (rare) |
| `OCI_CLI_FINGERPRINT` | `db-backup.yml` | When the backup user’s API key is rotated |
| `OCI_CLI_KEY_CONTENT_B64` | `db-backup.yml` | Base64 of the backup user’s PEM API key (single source of truth) |
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

Terraform may assign a **different public IP** when an instance is destroyed and recreated (observed in issue #148).

With DuckDNS (issue #523):

1. `task tf:oci:apply` (or `terraform apply`) runs `null_resource.duckdns_*` and updates the A record to the new IP (requires `duckdns_domain` / `duckdns_domain_staging` in `terraform.tfvars` + `TF_VAR_duckdns_token`).
2. The optional `linuxserver/duckdns` sidecar (compose profile `ddns`) also keeps the A record fresh after deploy.
3. If `OCI_VM_HOST` / `OCI_STAGING_VM_HOST` still stores the **raw IP**, update it after apply. Prefer storing the same FQDN as `OCI_DOMAIN` / `OCI_DOMAIN_STAGING` so SSH targets stay stable.

```bash
# After terraform apply, confirm DNS + IPs
cd terraform/oci
terraform output instance_v2_public_ip            # production
terraform output instance_staging_public_ip       # staging
terraform output app_url                          # https://$OCI_DOMAIN when configured
dig +short "$(gh variable get OCI_DOMAIN)"

# Repo variables (non-secret FQDNs) — set once, change only if hostname changes
gh variable set OCI_DOMAIN --body "YOUR_PROD_FQDN"
gh variable set OCI_DOMAIN_STAGING --body "YOUR_STAGING_FQDN"

# Only needed if secrets still hold the raw IP (not the DuckDNS hostname)
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

On OCI, images use **local storage** only (`UPLOAD_DIR`, volume `uploads`):
- Stored in Docker volume `uploads`
- Served at `https://$OCI_DOMAIN/uploads/<uuid>.<ext>` (staging: `$OCI_DOMAIN_STAGING`)
- Caddy proxies `/uploads/*` to the backend

Compose may still set `IMAGE_STORAGE=local` for clarity; other values are
ignored (Firebase/GCS image storage was removed — #458).

## Differences from GCP Deployment

| Aspect | GCP | OCI |
|--------|-----|-----|
| Backend | Cloud Run (serverless) | Docker on ARM VM |
| Frontend | Firebase Hosting (CDN) | Nginx on same VM |
| Database | Docker on e2-micro VM | Docker on same ARM VM |
| SSL | Managed by Cloud Run/Firebase | Caddy + Let's Encrypt (DuckDNS; nip.io redirects) |
| Image Storage | GCS bucket | Local Docker volume |
| DB backups | GCS (retired, #383) | Object Storage `ymatch-db-backups` |
| Auto-scaling | Yes (Cloud Run) | No (single VM) |
| Cost | Free tier (multiple services) | Free tier (VMs + Object Storage) |
| Public IP | Removed to save $3.60/mo | Included free |

## Teardown

**Danger:** `terraform/oci` manages **both** compute (VMs) **and** the off-VM
backup bucket (`ymatch-db-backups`).

`lifecycle.prevent_destroy = true` is set **only on the bucket**. A full
`terraform destroy` will still destroy VMs, networking, the object lifecycle
policy, and the `ymatch-db-backup` upload IAM user/group/policy, then **fail**
when it tries to destroy the bucket. That is **not** a no-op: automation and
compute can already be gone while objects remain without rotation or upload
credentials.

Always prefer **targeted** destroy for compute (section 2). Download dumps
first (section 1) before any destroy that could touch Object Storage or backup
automation.

### 1. Download backups before any destroy that could touch Object Storage

```bash
NS="$(oci os ns get --query data --raw-output)"
oci os object list --namespace "$NS" --bucket-name ymatch-db-backups --all
# Pull what you need, e.g.:
oci os object get \
  --namespace "$NS" \
  --bucket-name ymatch-db-backups \
  --name daily/ymatch-YYYY-MM-DD.sql.gz \
  --file backup.sql.gz
```

### 2. Destroy compute only (keep Object Storage backups)

Use targeted destroy for VMs/network if you intend to keep dumps:

```bash
cd terraform/oci
# Example — adjust targets to the resources you intend to remove
terraform destroy \
  -target=oci_core_instance.ymatch_v2 \
  -target=oci_core_instance.ymatch_staging
```

### 3. Intentionally retire the backup bucket

1. Download remaining objects (step 1).
2. Remove the `lifecycle { prevent_destroy = true }` block from
   `oci_objectstorage_bucket.db_backups` in `backup.tf`.
3. `terraform apply` (accept the lifecycle change).
4. `terraform destroy -target=oci_objectstorage_bucket.db_backups` (and related
   lifecycle policy / upload IAM if retiring the whole feature).

### 4. Full stack destroy (after step 3)

```bash
cd terraform/oci
terraform destroy
```

This removes VMs, VCN, subnet, internet gateway, security list, **and** (once
unlocked) the backup bucket, lifecycle policy, and backup IAM user/group/policies.

> **Note**: Boot volumes and their data are destroyed with the instances. Prefer
> Object Storage dumps for recovery — see
> [monitoring_setup.md](./monitoring_setup.md#5-database-backup-monitoring).

## Database backups (Object Storage)

Daily backups run via `.github/workflows/db-backup.yml`: SSH to production → `pg_dump | gzip` →
upload to bucket **`ymatch-db-backups`** (Terraform: `terraform/oci/backup.tf`). Lifecycle rules
delete `daily/` after 7 days, `weekly/` after 28 days, and `monthly/` after 90 days.

### One-time setup of OCI CLI secrets for the backup workflow

Use the **least-privilege** `ymatch-db-backup` user created by Terraform (not the
Terraform admin API key). After `terraform apply`:

```bash
cd terraform/oci
USER_OCID="$(terraform output -raw db_backup_user_ocid)"
TENANCY="$(grep '^tenancy_ocid' terraform.tfvars | cut -d'"' -f2)"
REGION="$(grep '^region' terraform.tfvars | head -1 | cut -d'"' -f2)"

# Generate a dedicated RSA key for this user only
openssl genrsa -out ~/.oci/ymatch_db_backup.pem 2048
chmod 600 ~/.oci/ymatch_db_backup.pem
openssl rsa -pubout -in ~/.oci/ymatch_db_backup.pem \
  -out ~/.oci/ymatch_db_backup_public.pem

# Upload the public key (Console: Identity → Users → ymatch-db-backup → API Keys)
# or via CLI:
oci iam user api-key upload \
  --user-id "$USER_OCID" \
  --key-file ~/.oci/ymatch_db_backup_public.pem
# Note the fingerprint from the command output / Console

gh secret set OCI_CLI_USER --body "$USER_OCID"
gh secret set OCI_CLI_TENANCY --body "$TENANCY"
gh secret set OCI_CLI_FINGERPRINT --body "<fingerprint-from-upload>"
gh secret set OCI_CLI_REGION --body "$REGION"
# Single key secret (base64 PEM — reliable multiline handling in Actions)
base64 -w0 ~/.oci/ymatch_db_backup.pem | gh secret set OCI_CLI_KEY_CONTENT_B64
# Optional cleanup if an older raw-PEM secret was ever set:
# gh secret delete OCI_CLI_KEY_CONTENT 2>/dev/null || true
```

The group policy only allows `read buckets` plus object
create/overwrite/inspect/read on `ymatch-db-backups` (no `OBJECT_DELETE`).
Lifecycle expiry deletes use the Object Storage **service** principal, not CI.

After the first successful run, confirm the object exists:

```bash
NS="$(oci os ns get --query data --raw-output)"
oci os object head \
  --namespace "$NS" \
  --bucket-name ymatch-db-backups \
  --name daily/ymatch-YYYY-MM-DD.sql.gz
```
