# Disaster Recovery

This document describes how the ymatch OCI deployment is recovered
when a production VM is lost or needs to be recreated, and captures the
lessons learned from the end-to-end test performed in June 2026
(see [issue #148](https://github.com/menonu/ymatch/issues/148)).

## When to Recover

The recovery procedure is triggered when:

- The VM's SSH key is lost (the original incident in June 2026)
- The VM is destroyed and cannot be restarted
- The VM's underlying boot volume is corrupted
- The tenancy needs to be migrated

If only the application is broken but the VM is reachable, prefer a
**redeploy** (see `oci_deploy_production.sh`) over a full recovery.

## Overview of the Recovery Procedure

1. Generate a new SSH key pair for VM access
2. Add the new public key to Terraform's `ssh_public_key_v2` variable
3. Run `terraform apply` to provision a replacement instance
4. Wait for cloud-init to complete (Docker, NR agent, ports)
5. Sync the repo to the new VM (rsync, clone, or pull)
6. Run `oci_deploy_production.sh` with the production DB password
7. Update GitHub Secrets:
   - `OCI_VM_HOST` to the new public IP
   - `OCI_SSH_PRIVATE_KEY` only if the SSH key was rotated
8. Verify the app via HTTPS and `/api/v1/system/status`

The full procedure is in [how_to/oci_deployment.md](../how_to/oci_deployment.md).
This document focuses on the **lessons learned** that aren't obvious
from the deployment guide.

## End-to-End Test (June 2026)

The procedure was validated on the `test/redeploy-with-new-scripts`
branch which merged PRs #146 and #147.

### Test Scenario

1. Create test branch with both fixes
2. `terraform destroy -target=oci_core_instance.ymatch_v2` to remove the running instance
3. `terraform apply` to recreate with the new cloud-init
4. Wait for cloud-init completion (~80 seconds)
5. rsync the new code (`.git` excluded) to the new instance
6. Run the new `oci_deploy_production.sh` from PR #147
7. Verify HTTPS frontend and API return 200
8. Run `oci_redeploy_backend.sh` to test the redeploy path

### Results

| Check | Before the fixes | After the fixes |
|-------|------------------|-----------------|
| `cloud-init status` | `error` (oci-cli pip failure) | **`done`** |
| SSH to new instance | Works | Works |
| rsync (no `.git`) deploy | `git pull` fatal error | Skipped + succeeded |
| HTTPS Frontend | HTTP 200 | HTTP 200 (~0.3s) |
| HTTPS API | HTTP 200 | HTTP 200 (~0.3s) |
| DB migrations | OK | OK |
| Backend listen + matching | OK | OK |
| `oci_redeploy_backend.sh` | `STAGING_DB_PASSWORD` error | Works |

## Key Lessons Learned

### 1. The public IP changes when an instance is recreated

OCI does not guarantee the same public IP when an instance is
destroyed and recreated. In the test, the IP went from
`217.142.234.210` to `<redacted>`.

**Implication**: every recreate requires updating the GitHub Secret
`OCI_VM_HOST` before the next CI deploy. The deploy workflows will
fail with SSH connection errors if the secret is stale.

**Mitigation options** (not yet implemented):

- **OCI Reserved Public IP**: assign a static IP at the subnet level
  and reattach it after recreate. Small additional cost (Always Free
  may not cover this).
- **Floating IP with a regional pool**: similar to above.
- **DNS-based**: instead of storing the IP in a secret, store a
  hostname that points to a managed DNS record. The recovery
  procedure updates the DNS A record instead of the GitHub secret.

For now, the manual procedure is: after `terraform apply`, get the
new IP from `terraform output` and run `gh secret set OCI_VM_HOST
--body "<new-ip>"`.

### 2. cloud-init success/failure status is not just cosmetic

The `cloud-init status` is used by monitoring and CI to determine
whether a fresh VM is ready. The original `oci-cli` install failure
made the whole script report `error`, even though Docker, the NR
agent, and the iptables rules were all set up correctly.

This caused false alarms in monitoring and was a real bug, not just
a cosmetic issue. The fix (PR #146) removed the `oci-cli` block.

### 3. The OCI API key does not survive across users

When provisioning a new instance or a new IAM user, the OCI API key
pair must be regenerated. The fingerprint changes. This is a
**different credential** from the SSH key used to log into the VM.

The setup procedure is documented in
[how_to/oci_credentials.md](../how_to/oci_credentials.md). The
non-obvious gotcha is that the OCI Console rejects ed25519 keys
("Invalid public key header or footer") — only RSA 2048 is accepted.

### 4. Redeploy scripts need all env vars, not just the ones for the target service

The `docker-compose.oci.yml` validates **all** services at parse
time, not just the ones being deployed. When production and staging
shared a single VM and compose file, this meant redeploying just
`ymatch_backend` required `STAGING_DB_PASSWORD` to be set, because
the compose file referenced both production and staging services.

The fix in PR #147 was to **always regenerate the `.env` file** at
the start of any deploy or redeploy, ensuring all required variables
are present.

> **Update (#209):** production and staging now run on separate VMs
> with a single-stack compose file, so the cross-environment
> validation no longer applies — redeploying `ymatch_backend` only
> needs `DB_PASSWORD`. The "always regenerate `.env`" practice from
> #147 is still followed.

### 5. GitHub Actions `GITHUB_TOKEN` rotates per run

When the workflows SSH to the VM and run `git fetch`, the previous
run's token is no longer valid. The fix (PR #150) is to call
`git remote set-url origin` on every run with the new token, so
`origin` always points to a URL that works with the current
run's credentials.

### 6. The deploy script's `.env` file must use shell-safe quoting

The first implementation of `oci_write_compose_env` used bash
`printf %q`, which produced output that worked in bash but not in
zsh. The fix was to delegate quoting to Python's `shlex.quote`,
which produces a string that can be `source`d by any POSIX shell.

## What Still Needs Improvement

These items are tracked in the issue tracker:

- **#140**: OCI billing → NR integration via local cron (currently
  missing because `oci-cli` doesn't work on the VM)
- **#142**: Plan to decommission the original `ymatch-arm` instance
  once the new one is proven stable
- **#144**: Integrated `recover_production.sh` script that wraps the
  full procedure in one command (reduces manual steps further)

## Related

- [how_to/oci_deployment.md](../how_to/oci_deployment.md) — full
  deployment procedure
- [how_to/oci_credentials.md](../how_to/oci_credentials.md) —
  OCI API key management
- [Issue #148](https://github.com/menonu/ymatch/issues/148) —
  E2E test report (this document's source)
- PR #146 — cloud-init fix (oci-cli removal, display_name var)
- PR #147 — deploy script refactor (rsync support, .env handling)
- PR #150 — workflow refactor (new deploy scripts, GH_TOKEN rotation)
