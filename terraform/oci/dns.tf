# ---------------------------------------------------
# DuckDNS (stable public hostnames — issue #523)
# ---------------------------------------------------
# Account + subdomain creation is out-of-band at duckdns.org.
# On apply (and whenever instance public_ip changes), push the A record.
# Continuous keep-alive on the VM is the linuxserver/duckdns sidecar
# (docker-compose.oci.yml profile "ddns").

locals {
  duckdns_enabled = var.duckdns_token != ""
  duckdns_update  = abspath("${path.module}/../../scripts/duckdns_update.sh")
}

# Fail plan/apply early if token is set but subdomains were left empty
# (avoids publishing an empty domains= query to DuckDNS).
check "duckdns_domains_when_token_set" {
  assert {
    condition = !local.duckdns_enabled || (
      var.duckdns_domain != "" && var.duckdns_domain_staging != ""
    )
    error_message = "When TF_VAR_duckdns_token is set, duckdns_domain and duckdns_domain_staging must be non-empty in terraform.tfvars (bare subdomains; keep in sync with GitHub vars OCI_DOMAIN / OCI_DOMAIN_STAGING)."
  }
}

resource "null_resource" "duckdns_prod" {
  count = local.duckdns_enabled ? 1 : 0

  triggers = {
    ip     = oci_core_instance.ymatch_v2.public_ip
    domain = var.duckdns_domain
    # Bump when the update script changes so re-apply re-runs DNS.
    script = filesha256(local.duckdns_update)
  }

  provisioner "local-exec" {
    environment = {
      DUCKDNS_DOMAIN = var.duckdns_domain
      DUCKDNS_TOKEN  = var.duckdns_token
      DUCKDNS_IP     = oci_core_instance.ymatch_v2.public_ip
    }
    command = local.duckdns_update
  }
}

resource "null_resource" "duckdns_staging" {
  count = local.duckdns_enabled ? 1 : 0

  triggers = {
    ip     = oci_core_instance.ymatch_staging.public_ip
    domain = var.duckdns_domain_staging
    script = filesha256(local.duckdns_update)
  }

  provisioner "local-exec" {
    environment = {
      DUCKDNS_DOMAIN = var.duckdns_domain_staging
      DUCKDNS_TOKEN  = var.duckdns_token
      DUCKDNS_IP     = oci_core_instance.ymatch_staging.public_ip
    }
    command = local.duckdns_update
  }
}
