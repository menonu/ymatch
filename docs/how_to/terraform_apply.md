# Applying Terraform with Secrets (TF_VAR_ + .env)

How to run `terraform plan` / `apply` for the `terraform/newrelic` and
`terraform/oci` modules **without ever putting a secret or host
identifier in the repo**. This is the IaC privacy workflow (#284).

## Principles

- The committed `.tf` files contain **no secrets and no identifiers** —
  only references like `var.api_key`, `var.app_public_ip`.
- All real values are supplied at apply time and are **gitignored**:
  - `terraform/<module>/terraform.tfvars` — non-secret config (OCIDs,
    region, sizing, SSH public keys, `app_public_ip`, `nr_display_name`).
  - `terraform/<module>/.env` — secrets as `TF_VAR_*` env vars
    (`api_key`, `nr_license_key`, `discord_webhook_url`, `db_password`,
    `alert_email`, …).
- Secret vars are marked `sensitive = true` in `variables.tf`, so
  `terraform plan` redacts them in its output.

## Precedence caveat (important)

Terraform variable precedence (low → high): variable default →
`TF_VAR_*` env → `terraform.tfvars` → `*.auto.tfvars` → `-var-file` →
`-var`.

**`terraform.tfvars` overrides `TF_VAR_*` env vars.** So a given
variable must live in **only one** of the two files:

- Secrets → `.env` only (never also in `terraform.tfvars`).
- Non-secret config → `terraform.tfvars` only.

If a secret is left in `terraform.tfvars` after migrating to `.env`,
the tfvars value wins and `.env` is silently ignored for that var.

## One-time setup

```bash
# newrelic
cp terraform/newrelic/terraform.tfvars.example terraform/newrelic/terraform.tfvars
#   edit terraform.tfvars: account_id, region, app_public_ip
cp terraform/newrelic/.env.example            terraform/newrelic/.env
#   edit .env: TF_VAR_api_key, TF_VAR_nr_license_key, TF_VAR_discord_webhook_url
task tf:newrelic:init

# oci
cp terraform/oci/terraform.tfvars.example terraform/oci/terraform.tfvars
#   edit terraform.tfvars: OCIDs, region, SSH public keys, sizing, nr_display_name
cp terraform/oci/.env.example                 terraform/oci/.env
#   edit .env: TF_VAR_db_password, TF_VAR_nr_license_key, TF_VAR_nr_account_id, TF_VAR_alert_email
cp terraform/oci/backend.hcl.example          terraform/oci/backend.hcl
#   edit backend.hcl: namespace (oci os ns get), region
task tf:oci:init
```

Both `terraform.tfvars` and `.env` are gitignored (`**/.env` and the
`terraform/*/terraform.tfvars` entries in `.gitignore`). The
`*.example` templates are committed.

## Day-to-day

The `task` targets source `.env` automatically, so you never export
secrets by hand:

```bash
task tf:newrelic:plan     # sources .env, runs terraform plan
task tf:newrelic:apply    # sources .env, runs terraform apply
task tf:oci:plan
task tf:oci:apply
```

Review the plan (especially for `oci`, which spans many resources)
before applying.

## Migrating from an all-in-`terraform.tfvars` setup

If your existing `terraform.tfvars` still contains secrets (e.g.
`db_password`, `api_key`), move each one to `.env` as a `TF_VAR_*` line
and **delete it from `terraform.tfvars`** — otherwise tfvars wins and
`.env` is ignored for that var (see the precedence caveat above).

## What stays out of the repo

- `terraform/*/terraform.tfvars` (gitignored)
- `terraform/*/.env` (gitignored via `**/.env`)
- `terraform/*/backend.hcl` (gitignored — contains the tenancy Object
  Storage namespace)
- `terraform/*/terraform.tfstate*` (gitignored; the `oci` module now
  stores state remotely in OCI Object Storage — see below — so the local
  file is only a stale pre-migration copy)
- `terraform/*/.terraform/` (gitignored provider cache)

Only `.tf`, `*.tfvars.example`, `.env.example`, and `backend.hcl.example`
are committed, and they contain only placeholders — never real values.

## Remote state backend (OCI module)

The `terraform/oci` module stores state in an **OCI Object Storage**
bucket (`ymatch-tfstate`) rather than a local file, so state is shared
across machines and protected by Object Storage locking (#302). The
bucket is created out-of-band (it can't be managed by the config that
stores its state in it) and the tenancy-specific backend values live in
the gitignored `backend.hcl`.

### One-time bucket bootstrap

```bash
# Object Storage namespace for your tenancy
oci os ns get                       # e.g. "axsxw8hyxmch"

# Create the state bucket in the root compartment (tenancy) with
# versioning so state history is recoverable.
TENANCY=$(grep '^tenancy' ~/.oci/config | awk '{print $3}')
oci os bucket create --name ymatch-tfstate --compartment-id "$TENANCY" --versioning Enabled
```

### Point the module at the backend

```bash
cd terraform/oci
cp backend.hcl.example backend.hcl
#   edit backend.hcl: namespace (from `oci os ns get`), region
task tf:oci:init      # runs: terraform init -backend-config=backend.hcl
```

If you have an existing local `terraform.tfstate`, migrate it to the
remote backend (one-time):

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

After migration, `task tf:oci:plan` / `task tf:oci:apply` read and write
state through the remote backend automatically — no tarball/scp of state
files between machines.