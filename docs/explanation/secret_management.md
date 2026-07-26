# Secret Management

How ymatch stores, injects, and rotates secrets across **local Terraform
apply**, **GitHub Actions**, **OCI infrastructure**, and **runtime** on
the VMs. This is the operator-facing map of the secrets lifecycle.

For the public-repo **what must never be committed** policy, see
[Repository Security](security.md). For step-by-step Terraform apply, see
[Applying Terraform with Secrets](../how_to/terraform_apply.md). For
CI secret tables and deploy, see
[OCI Production Deployment](../how_to/oci_deployment.md).

Epic tracking the hardening roadmap: **#529**.

---

## Mental model (read this first)

Three stores look similar and are often confused:

| Store | What it is | Supplies secrets as *inputs* to plan/apply? | May *contain* secrets after apply? |
|-------|------------|-----------------------------------------------|------------------------------------|
| **Local `terraform/<module>/.env`** (`TF_VAR_*`) | Operator machine only; gitignored (#284) | **Yes** | N/A (not shared) |
| **GitHub Secrets / Variables** | CI/CD injection for workflows | **Yes** for Actions only | No (GitHub holds them) |
| **OCI Object Storage `ymatch-tfstate`** | Remote **Terraform state** + lock + versions (#302 / #307) | **No** | **Yes** — resource attributes (e.g. instance `user_data`) can embed secrets |
| **OCI Vault** | Managed secret service | **Not used yet** (#531) | N/A until adopted |

**Remote state is not a secrets manager.** Terraform cannot “load the DB
password from the state bucket” as a designed input path. State is the
record of what was applied; some secret material is unfortunately
*copied into* that record today (see [Secrets in state](#secrets-in-state-today)).

```text
  Operator laptop                    GitHub Actions
  ───────────────                    ──────────────
  ~/.oci/config  ──┐                 secrets.*  ──┐
  terraform/*/.env ┼── TF plan/apply              ├── deploy / backup workflows
  terraform/*.tfvars┘                             └── vars (non-secret FQDNs)
         │                                    │
         ▼                                    ▼
  OCI API ── create/update resources     SSH + compose on VMs
         │
         ▼
  Object Storage ymatch-tfstate
  (state JSON; may embed secrets)
```

---

## Where each class of value lives

### Non-secret config (safe in gitignored tfvars, not in git)

| Value | Local | GitHub | Notes |
|-------|-------|--------|-------|
| OCI tenancy / user / compartment OCIDs | `terraform/oci/terraform.tfvars` | CLI secrets for backup user | Identifiers, not passwords — still **do not commit** (public repo + privacy) |
| Region, shape, OCPU/memory | tfvars | — | |
| SSH **public** keys | tfvars | — | Private keys are secrets |
| DuckDNS bare subdomains (`ymatch`, `ymatch-staging`) | `duckdns_domain*` in tfvars | Vars `OCI_DOMAIN` / `OCI_DOMAIN_STAGING` (full FQDN) | Keep first DNS label aligned |
| New Relic display names, `app_public_url` | tfvars | — | URL is not secret |

### Secrets (never commit)

| Secret | Local Terraform | GitHub | Runtime / other |
|--------|-----------------|--------|-----------------|
| DuckDNS account token | `TF_VAR_duckdns_token` in `terraform/oci/.env` | Secret `DUCKDNS_TOKEN` | VM compose profile `ddns` via deploy `.env` |
| New Relic **ingest** license key | `TF_VAR_nr_license_key` (oci + newrelic `.env`) | `NEW_RELIC_LICENSE_KEY` | Historically also in instance **cloud-init `user_data`** → **state** (#305) |
| New Relic **user** API key | `TF_VAR_api_key` in `terraform/newrelic/.env` | — | NR Terraform provider |
| New Relic account id | `TF_VAR_nr_account_id` (oci); `account_id` in NR tfvars | `NEW_RELIC_ACCOUNT_ID` | Treat as sensitive identifier |
| Discord alert webhook | `TF_VAR_discord_webhook_url` (newrelic `.env`) | `DISCORD_WEBHOOK_URL` | |
| Budget alert email | `TF_VAR_alert_email` (oci `.env`) | — | OCI budget recipients |
| DB backup user email | `TF_VAR_db_backup_user_email` | — | OCI Identity user attribute (not a password) |
| `db_password` TF var | `TF_VAR_db_password` in oci `.env` | — | **Declared but unused** by current OCI resources; production DB passwords are **not** this var |
| Production / staging DB passwords | — | `OCI_DB_PASSWORD` / `OCI_STAGING_DB_PASSWORD` | Injected by deploy scripts into VM compose env |
| SSH **private** keys | `~/.ssh/…` (operator) | `OCI_SSH_PRIVATE_KEY` / `OCI_STAGING_SSH_PRIVATE_KEY` | VM `authorized_keys` has the public half only |
| VM SSH host | — | Secrets `OCI_VM_HOST` / `OCI_STAGING_VM_HOST` | Prefer DuckDNS FQDN once verified (#526 optional) |
| OCI API signing key (operator) | `~/.oci/*.pem` + config | — | Terraform provider + CLI; see [oci_credentials](../how_to/oci_credentials.md) |
| OCI API key (db-backup user) | optional local | `OCI_CLI_*` + `OCI_CLI_KEY_CONTENT_B64` | Backup workflow only |

Templates (placeholders only) live in:

- `terraform/oci/.env.example`, `terraform/oci/terraform.tfvars.example`
- `terraform/newrelic/.env.example`, `terraform/newrelic/terraform.tfvars.example`
- `backend/.env.example`

---

## Day-to-day operations

### Terraform plan / apply (local)

1. One-time: copy `*.example` → real `terraform.tfvars`, `.env`, `backend.hcl` (all gitignored).
2. Fill **secrets only** in `.env` as `TF_VAR_*`; non-secrets in `terraform.tfvars`.
3. Auth: valid `~/.oci/config` (or equivalent) for the OCI provider and the Object Storage backend.
4. Run:

```bash
task tf:oci:plan      # sources terraform/oci/.env
task tf:oci:apply
task tf:newrelic:plan
task tf:newrelic:apply
```

Precedence: **`terraform.tfvars` overrides `TF_VAR_*`**. A secret left in
tfvars silently wins over `.env` — see
[terraform_apply.md](../how_to/terraform_apply.md).

### CI deploy

Workflows read **GitHub Secrets/Variables**, not the operator’s local
`.env`. Updating a local file does **not** change production until the
matching GH secret/var is updated (or the next deploy uses the old value).

Procedure: [GitHub Secrets Management](../how_to/oci_deployment.md#github-secrets-management).

### Runtime on the VM

Deploy scripts write a host-local `.env` (DB password, `DOMAIN`, optional
`DUCKDNS_TOKEN`) used by Compose/Caddy. That file is **not** Terraform
state and is **not** in git.

---

## Secrets in state (today)

Known leakage path (tracked by **#305**):

- OCI instances set `metadata.user_data = base64encode(cloud-init)`.
- Cloud-init embeds `echo "license_key: ${var.nr_license_key}"` for the
  New Relic infrastructure agent.
- Terraform state stores `user_data`; base64-decoding recovers the license
  key. `sensitive = true` on the variable **only redacts plan/apply UI**,
  not state contents.

Mitigations in flight:

| Phase | Issue | Intent |
|-------|-------|--------|
| 2 | #305 | KMS/BYOK on `ymatch-tfstate`; stop baking NR key into `user_data` |
| 3 | #531 | OCI Vault (or equivalent) as shared **input** source |

Until then: treat access to the state bucket and to `~/.oci` credentials
that can read it as **equivalent to holding the NR ingest key** (and any
other values that have ever been written into managed resources).

`lifecycle { ignore_changes = [metadata, …] }` on instances means later
license rotations in Terraform **do not** rewrite VMs automatically; old
material can remain in **state history** (Object Storage versioning).

---

## Roadmap (epic #529)

| Phase | Issue | Outcome |
|-------|-------|---------|
| **1 — Operate** | #526 | DuckDNS `null_resource`s in remote state; NR synthetics on DuckDNS URL; optional stable SSH host secrets |
| **2 — Harden state** | #305 | Customer-managed encryption on state bucket; secrets out of `user_data` / state |
| **3 — Managed inputs** | #531 | Shared secret source (OCI Vault design + bootstrap) so a new operator machine does not rely on chat-pasted `.env` |
| **Docs** | #530 (this document) | Single map of the lifecycle |

Phase 3 must avoid chicken-and-egg: Vault bootstrap is **out-of-band**
(like the state bucket), not created by the same root module that needs
the secrets to plan.

---

## Bootstrap: new operator machine

Minimal path to run Terraform safely:

1. **OCI API key** — [oci_credentials.md](../how_to/oci_credentials.md); `~/.oci/config` working (`oci iam region list`).
2. **Clone repo**; do not commit gitignored files.
3. **Remote state backend**
   ```bash
   cp terraform/oci/backend.hcl.example terraform/oci/backend.hcl
   # set namespace (oci os ns get) + region
   cp terraform/newrelic/backend.hcl.example terraform/newrelic/backend.hcl
   task tf:oci:init
   task tf:newrelic:init
   ```
4. **Non-secret tfvars** — copy examples; fill OCIDs, SSH **public** keys, DuckDNS bare names, NR `app_public_url`, etc. Prefer copying from a trusted existing operator machine over retyping OCIDs.
5. **Secrets `.env`** — copy examples; fill from:
   - Password manager / break-glass export (preferred),
   - **Not** from git history,
   - **Not** from “read GitHub secret” (values are not retrievable after `gh secret set`),
   - Future: Vault (#531).
6. **`task tf:oci:plan`** — review; expect no unexpected destroys. Confirm DuckDNS domains when token is set.
7. Never paste production secrets into chat, issues, or PR bodies.

### Reconstructing `.env` when Vault is not available

| Variable | Practical recovery |
|----------|-------------------|
| `TF_VAR_duckdns_token` | DuckDNS account UI; same value as GH `DUCKDNS_TOKEN` (re-set both if rotated) |
| `TF_VAR_nr_license_key` | New Relic UI (ingest license); align GH `NEW_RELIC_LICENSE_KEY` |
| `TF_VAR_api_key` | New Relic user API key UI |
| `TF_VAR_nr_account_id` / NR `account_id` | NR account settings |
| `TF_VAR_discord_webhook_url` | Discord channel integrations; GH `DISCORD_WEBHOOK_URL` |
| `TF_VAR_alert_email` | Current value is in state (`oci_budget_alert_rule`) if you can `terraform state show` |
| `TF_VAR_db_backup_user_email` | State / OCI Identity user `ymatch-db-backup` |
| `TF_VAR_db_password` | Unused by resources today; placeholder acceptable for plan until removed or wired |
| DB passwords for **deploy** | Not in TF state by design; password manager or break-glass only; GH secrets are write-only |

---

## Rotation cheatsheet

| Secret | Rotate at source | Update local | Update CI | Update runtime |
|--------|------------------|--------------|-----------|----------------|
| DuckDNS token | duckdns.org | `terraform/oci/.env` | `DUCKDNS_TOKEN` | Redeploy with new token / sidecar env |
| NR ingest license | New Relic | oci + newrelic `.env` | `NEW_RELIC_LICENSE_KEY` | Agent config on VMs (not only Terraform, while #305 open) |
| NR user API key | New Relic | `terraform/newrelic/.env` | — | Re-apply NR module |
| Discord webhook | Discord | newrelic `.env` | `DISCORD_WEBHOOK_URL` | Re-apply NR notifications |
| DB password | Generate new; migrate DB users | — | `OCI_*_DB_PASSWORD` | Redeploy / update compose env on VM |
| SSH key pair | `ssh-keygen` | tfvars **public** key → instance (recreate or console) | `OCI_*_SSH_PRIVATE_KEY` | |
| OCI API key | Console upload | `~/.oci` | `OCI_CLI_*` if backup user | |
| `OCI_VM_HOST` | After IP change **or** switch to DuckDNS FQDN | — | `gh secret set` | |

After any rotation that was ever committed or pasted: follow
[security.md — History Is Public Too](security.md#history-is-public-too)
(rotate → redact history if needed → update all consumers).

---

## Recovery touchpoints

| Scenario | Secrets angle |
|----------|----------------|
| VM recreated | Public IP may change; DuckDNS A record should update via Terraform `null_resource` + optional sidecar (#523 / #526). Prefer `OCI_VM_HOST` = FQDN. |
| Lost SSH private key | New keypair; update tfvars public key + GH private key secret; see deployment guide. |
| Lost OCI API key | [oci_credentials.md](../how_to/oci_credentials.md); cannot use Vault or state until CLI auth works. |
| Lost local `.env` | Reconstruct table above; do not invent production DB passwords from TF state. |
| State bucket compromise | Assume secrets embedded in state are burned (#305); rotate NR license and review other attributes. |
| Full DR | [disaster_recovery.md](disaster_recovery.md) |

---

## Related documents

| Doc | Role |
|-----|------|
| [security.md](security.md) | Public-repo policy; never-commit list |
| [terraform_apply.md](../how_to/terraform_apply.md) | TF_VAR / `.env` / remote backend how-to |
| [oci_deployment.md](../how_to/oci_deployment.md) | Deploy + GitHub secrets matrix |
| [oci_credentials.md](../how_to/oci_credentials.md) | API key lifecycle |
| [disaster_recovery.md](disaster_recovery.md) | VM loss / recreate |
| [monitoring_setup.md](../how_to/monitoring_setup.md) | NR / synthetics URLs |

## Related issues

- Epic **#529** — secrets lifecycle + state hardening
- **#530** — this documentation
- **#526** — post-DuckDNS Terraform / NR apply
- **#305** — KMS + secrets out of state
- **#531** — OCI Vault / managed secret source
- **#284**, **#302**, **#307** — privacy workflow and remote state (done)
