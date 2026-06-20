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
- `terraform/*/terraform.tfstate*` (gitignored — and **contains secrets**,
  so never share it; a remote encrypted backend is a future hardening
  step)
- `terraform/*/.terraform/` (gitignored provider cache)

Only `.tf`, `*.tfvars.example`, and `.env.example` are committed, and
they contain only placeholders — never real values.