# Repository Security

This document explains the security posture of the `ymatch` repository:
what must never be committed, where sensitive values live instead, and
how history is kept clean. It is the reference agents and contributors
should check before writing files that touch credentials, paths, or
infrastructure.

`ymatch` is operated as a **public repository with restrictive
contribution controls** (PR approval required, fork-PR workflow runs
require maintainer approval). Anything committed to git — including
past history — is visible to the public. Treat that as the baseline.

## What Must Never Be Committed

Never write any of the following into tracked files, commit messages,
or code:

- **Secrets of any kind** — API keys, license keys (e.g. New Relic
  ingest keys), private SSH keys, service-account JSON, database
  passwords, OAuth tokens, webhook URLs. No hardcoded defaults, not
  even as "fallback" values in shell scripts.
- **Cloud credentials** — OCI API signing keys (`*.pem`), `~/.oci/config`
  contents, GCP service-account keys, fingerprint values.
- **Host-specific absolute paths** — e.g. `/home/<user>/...`. These leak
  the local OS username and are non-portable. Use relative paths in
  documentation and `${HOME}` (or a documented env var) in compose files.
- **Personal identifiers (PII)** — personal email addresses (other than
  the project contact `admin@ymatch.com`), personal names, machine
  hostnames, SSH public-key comments that identify a person. Commit
  author metadata is exempt (it is git identity, not file content).
- **Terraform state** — `*.tfstate` and `*.tfstate.*.backup` contain
  resource IDs, service-account emails, and sometimes plaintext
  secrets. They are gitignored and must never be tracked.
- **Environment files** — `backend/.env`, `frontend/.env`, any `**/.env`
  except the `.env.example` templates.

## Where Sensitive Values Live Instead

| Value | Location | Why it's safe |
|-------|----------|---------------|
| CI/CD secrets (DB passwords, SSH keys, NR keys, Discord webhook, OCI host) | GitHub repository Secrets | not in the repo; injected per workflow run |
| Local dev config | `backend/.env` (gitignored), copied from `backend/.env.example` | gitignored |
| OCI CLI / Terraform auth | `~/.oci/config`, `terraform/oci/terraform.tfvars` (both gitignored) | local only |
| Terraform inputs | `terraform/oci/terraform.tfvars.example` (placeholders only) | template, no real values |
| VM cron env (cost exporters) | root-owned env file sourced before the cron, or `${VAR}` required | scripts fail fast with `:?` if missing |
| Role-grant username (operator) | runtime arg to `scripts/grant_role.sh <username> <role>`; per-env wrappers gitignored via `scripts/*local*` | the username is never written into a tracked file, so no PII is committed (ADR 0004 §6; see [Granting Global Roles](../how_to/grant_roles.md)) |

Scripts that need a secret must read it from an environment variable
and fail loudly if it is absent — never embed a real default. See
`scripts/gcp_cost_to_newrelic.sh` and `scripts/oci_cost_to_newrelic.sh`
for the pattern (`: "${NR_LICENSE_KEY:?... is required}"`).

## Gitignore Coverage

The repository `.gitignore` already excludes the sensitive file classes
above. Before adding a new generated/config artifact, check whether it
belongs there. Notable covered patterns:

- `backend/.env`, `frontend/.env`, `**/.env` (with `!.env.example` exceptions)
- `terraform/**/terraform.tfvars`, `terraform/**/.terraform/`, `*.tfstate*`
- `*.pem`, `*.log`, `*.pid`, `.firebase/`, `.task/`

If you are unsure whether a file is safe to commit, run
`git check-ignore -v <path>` — if it is ignored, do not force-add it.

## Runtime: debug guest-session overrides (#499)

The Flutter web app supports a **debug-only** multi-tab helper: the URL
param `dev_user` (query or hash fragment) can force a guest login with a
chosen UUID without writing SharedPreferences. That is useful for local
multi-account testing but must never ship to production:

- `AuthController.checkLogin` honors `dev_user` only when
  `enableDevSessionOverrides` is true (defaults to `kDebugMode`).
- The Admin **Debug** tab (which builds `…/#/?dev_user=…` links) is
  similarly gated and is absent from release builds.
- Guest UUIDs remain bearer secrets (SharedPreferences + Profile copy)
  until a real session-token model lands (#373). Do not paste production
  guest UUIDs into shareable URLs.

See [Developer Quickstart — multi-tab guest sessions](../tutorials/developer_quickstart.md#multi-tab-guest-sessions-debug-builds-only).

## History Is Public Too

A secret removed from the current tree is **not** removed from git
history. Anyone can check out an older commit and read it. The
repository's policy for a secret that was committed:

1. **Rotate** the secret at its source (revoke the old value so it is
   useless even if recovered from history).
2. **Redact** the historical occurrence with `git filter-repo
   --replace-text` and force-push, so the value is no longer in any
   reachable commit.
3. Update all consumers (GitHub Secrets, VM env, terraform tfvars) with
   the new value.

This was applied to the New Relic ingest key, an embedded SSH public-key
comment containing a personal identifier, and a terraform-state backup
that recorded a personal email. The cleanup bundle is kept as a restore
point until the next history rewrite is confirmed stable.

## Pre-Commit Checklist

Before committing anything that touches infra, scripts, or docs:

- [ ] No secret values in the diff (grep for `password`, `key`, `token`,
      `secret`, `NRAL`, `ocid1.`, long hex strings).
- [ ] No absolute `/home/...` or `/Users/...` paths; use relative or
      `${HOME}`.
- [ ] No real cloud resource OCIDs, account IDs, or billing IDs in
      examples — use `YOUR_*` placeholders.
- [ ] No personal emails or names in file content.
- [ ] No `*.tfstate*`, `*.pem`, or `.env` files staged
      (`git status` + `git check-ignore`).
- [ ] Any new script that uses a secret reads it from env with `:?` and
      has no hardcoded default.

## Related

- [OCI Credentials Management](../how_to/oci_credentials.md) — OCI API
  key generation, rotation, and loss recovery.
- [Development Workflow Guide](../how_to/development_workflow.md) — PR
  and CI workflow (trunk-based, human-only merge).
- [AGENTS.md](../../AGENTS.md) — agent conventions, including the
  security rule in a one-line form.