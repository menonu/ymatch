variable "account_id" {
  description = "New Relic Account ID"
  type        = number
  # Account identifier — redact from `terraform plan` output (the value
  # is still gitignored in terraform.tfvars; this is defense-in-depth).
  sensitive = true
}

variable "api_key" {
  description = "New Relic User API Key (NRAK-xxx)"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "New Relic region (US or EU)"
  type        = string
  default     = "US"
}

variable "app_public_ip" {
  description = "Public IP of the OCI VM running the app"
  type        = string
}

variable "discord_webhook_url" {
  description = "Discord webhook URL for alert notifications"
  type        = string
  sensitive   = true
}

variable "nr_license_key" {
  description = "New Relic Ingest License Key (for custom events)"
  type        = string
  sensitive   = true
}
