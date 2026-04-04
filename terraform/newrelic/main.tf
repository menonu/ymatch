terraform {
  required_providers {
    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.50"
    }
  }
}

provider "newrelic" {
  account_id = var.account_id
  api_key    = var.api_key
  region     = var.region
}

# ---------------------------------------------------
# Synthetic Monitors
# ---------------------------------------------------
resource "newrelic_synthetics_monitor" "api_health" {
  name             = "ymatch API Health (OCI)"
  type             = "SIMPLE"
  status           = "ENABLED"
  period           = "EVERY_15_MINUTES"
  uri              = "https://${var.app_public_ip}.nip.io/api/v1/events"
  locations_public = ["AP_NORTHEAST_1"]
  verify_ssl       = true

  treat_redirect_as_failure = false
  bypass_head_request       = false
}

resource "newrelic_synthetics_monitor" "frontend" {
  name             = "ymatch Frontend (OCI)"
  type             = "SIMPLE"
  status           = "ENABLED"
  period           = "EVERY_15_MINUTES"
  uri              = "https://${var.app_public_ip}.nip.io/"
  locations_public = ["AP_NORTHEAST_1"]
  verify_ssl       = true

  treat_redirect_as_failure = false
  bypass_head_request       = false
}
