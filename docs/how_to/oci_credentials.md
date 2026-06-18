# OCI Credentials Management

This guide covers the **OCI API signing key** used by Terraform and the OCI CLI to authenticate against Oracle Cloud Infrastructure. It is distinct from the **SSH key** used to log into the VM (see [OCI Deployment](./oci_deployment.md) for that).

## Overview

The ymatch project uses two kinds of credentials to interact with OCI:

| Credential | Purpose | Where stored | Format |
|-----------|---------|--------------|--------|
| **OCI API key** (RSA 2048) | Authenticates the OCI CLI / Terraform against OCI APIs | `~/.oci/oci_api_key.pem` (gitignored) | RSA 2048 PEM |
| **SSH key** (ed25519) | SSH into the VM | `~/.ssh/oci_ymatch[_v2]` (gitignored) | ed25519 |

This document covers the **OCI API key** only.

## Key Properties

| Property | Value | Why |
|----------|-------|-----|
| Algorithm | **RSA 2048** | OCI Console does not accept ed25519 ("Invalid public key header or footer") |
| Format | PEM (PKCS#8) | Required by OCI |
| File mode | 600 | OCI CLI refuses to use keys with broader permissions |
| Storage | **At least 2 places** (local + password manager) | Past incident: lost the only copy, blocked SSH into VM (#135) |

The corresponding public key is uploaded to OCI via the **User Settings → API Keys** console page. OCI returns a fingerprint that must be stored in `terraform.tfvars`.

---

## Initial Setup (One-Time)

This is the only step that requires a browser session. It cannot be scripted because uploading a public key requires prior authentication — which is exactly the credential we are trying to create (chicken-and-egg).

### Step 1: Generate the key pair locally

```bash
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem \
  -out ~/.oci/oci_api_key_public.pem
```

### Step 2: Calculate the fingerprint (for your records)

```bash
openssl rsa -pubin -in ~/.oci/oci_api_key_public.pem -outform DER \
  | openssl md5 -c
# Example output: ce:66:87:eb:62:8f:09:ae:0b:5c:15:71:07:5d:17:3d
```

The fingerprint will be displayed by the OCI Console after upload — **verify it matches**.

### Step 3: Upload the public key via OCI Console

1. OCI Console → top-right profile icon → **User Settings**
2. Left menu → **API Keys**
3. **Add API Key**
4. Select **Paste Public Key** and paste the contents of `~/.oci/oci_api_key_public.pem`
5. Click **Add**
6. The Console displays a **Configuration File Preview** showing the fingerprint and a snippet for `~/.oci/config`. Copy the fingerprint.

### Step 4: Create `~/.oci/config`

```ini
[DEFAULT]
user=ocid1.user.oc1..YOUR_USER_OCID
fingerprint=<fingerprint from step 2/3>
tenancy=ocid1.tenancy.oc1..YOUR_TENANCY_OCID
region=ap-osaka-1
key_file=/home/<user>/.oci/oci_api_key.pem
```

```bash
chmod 600 ~/.oci/config
```

### Step 5: Verify

```bash
oci iam user get --user-id ocid1.user.oc1..YOUR_USER_OCID
```

A JSON object with your user details confirms the key is working.

### Step 6: Update Terraform

In `terraform/oci/terraform.tfvars` (gitignored):

```hcl
fingerprint      = "<fingerprint from step 2/3>"
private_key_path = "/home/<user>/.oci/oci_api_key.pem"
```

`terraform.tfvars.example` is a safe template you can use as a reference.

### Step 7: Back up the private key

**Do not skip this.** Store `~/.oci/oci_api_key.pem` in at least one of:

- A password manager (1Password, Bitwarden, etc.)
- An encrypted backup (e.g. `gpg --symmetric` then upload to cloud storage)
- A second trusted machine

If you lose the only copy, you must delete the API key from OCI, generate a new one, and update `terraform.tfvars` / `~/.oci/config` everywhere they reference it.

---

## Using the API Key

### From the OCI CLI

`~/.oci/config` is read automatically. Example:

```bash
oci compute instance list --compartment-id <ocid>
```

### From Terraform

The `oracle/oci` provider reads `~/.oci/config` if no `provider "oci"` block specifies explicit values. To override, edit `terraform/oci/main.tf`:

```hcl
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
```

### From CI (GitHub Actions)

Add the **private key content** as a GitHub Secret (e.g. `OCI_API_KEY_PEM`) and write it to a file in the workflow:

```yaml
- name: Setup OCI credentials
  run: |
    mkdir -p ~/.oci
    echo "${{ secrets.OCI_API_KEY_PEM }}" > ~/.oci/oci_api_key.pem
    chmod 600 ~/.oci/oci_api_key.pem
    # ... write ~/.oci/config ...
```

The fingerprint and other fields are also secrets and should be set in the same way.

---

## Key Rotation

Oracle allows **up to 3 API keys per user**. Use this to rotate without downtime.

### Step-by-step

1. **Generate a new key pair** (don't delete the old one yet):

   ```bash
   openssl genrsa -out ~/.oci/oci_api_key_v2.pem 2048
   chmod 600 ~/.oci/oci_api_key_v2.pem
   openssl rsa -pubout -in ~/.oci/oci_api_key_v2.pem \
     -out ~/.oci/oci_api_key_v2_public.pem
   ```

2. **Upload the new public key** to OCI Console (same flow as initial setup). The console will show the new fingerprint.

3. **Verify the new key works**:

   ```bash
   OCI_USER_OCID=ocid1.user.oc1..aaaaaaaa...
   OCI_FINGERPRINT=<new fingerprint>
   OCI_KEY_FILE=~/.oci/oci_api_key_v2.pem oci iam user get --user-id "$OCI_USER_OCID"
   ```

   If this returns your user info, the new key is registered correctly.

4. **Update all consumers** to use the new key:
   - Local `~/.oci/config` — change `fingerprint` and `key_file`
   - `terraform/oci/terraform.tfvars` — change `fingerprint` and `private_key_path`
   - GitHub Secrets (e.g. `OCI_API_KEY_PEM`, `OCI_SSH_PRIVATE_KEY`) — re-paste the new private key

5. **Apply Terraform** to verify nothing is broken:

   ```bash
   cd terraform/oci
   terraform plan    # should show "No changes"
   ```

6. **Delete the old API key** from OCI Console once everything is confirmed working.

---

## Key Loss Recovery

If you lose the only copy of the private key:

1. **Generate a new key pair** (same as initial setup steps 1-2)
2. **Upload the new public key** via OCI Console — it will appear as a new entry alongside (or replacing) the lost one
   - If the old key still shows in the Console, you can delete it after the new one is verified
   - If the old key is gone (e.g. expired), just add the new one
3. **Update local config**: `~/.oci/config`, `terraform.tfvars`, GitHub Secrets
4. **Update Terraform state** — `terraform plan` should show no changes for resources, but you may need to re-apply if `fingerprint` is part of a state-tracked attribute
5. **Test deploys and CI runs**

See issue #135 for a real-world recovery scenario (SSH key loss led to provisioning a replacement VM at `ymatch-arm-v2`).

---

## Security Best Practices

- ✅ **Never commit** `~/.oci/config`, `*.pem`, or any file containing the private key. They are in `.gitignore`.
- ✅ **Restrict file permissions** to 600. The OCI CLI refuses to use keys with broader permissions.
- ✅ **Use a passphrase** for the OCI API key if you can — `openssl genrsa -aes128 -out ...` will prompt for one. Note: passphrase-protected keys are harder to use in CI/CD.
- ✅ **Audit regularly** — OCI Console → API Keys lists all registered keys. Remove any you don't recognize.
- ✅ **Use the right key for the right job** — keep the OCI API key separate from the SSH key. They are independent credentials.
- ❌ **Don't share** private keys via chat, email, or unencrypted storage.
- ❌ **Don't reuse** the OCI API key across multiple machines without thinking about access control.

---

## Related

- [OCI Deployment Guide](./oci_deployment.md) — VM provisioning, SSH key setup
- [Development Workflow](./development_workflow.md) — PR and CI workflow
- [Disaster Recovery](#) — TBD (issue #144)
- `terraform/oci/terraform.tfvars.example` — template
- [Issue #135](https://github.com/menonu/ymatch/issues/135) — original recovery scenario
- [Issue #136](https://github.com/menonu/ymatch/issues/136) — Terraform changes that depend on this
- [OCI API Signing Key docs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)
