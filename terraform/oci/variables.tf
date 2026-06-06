variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API Private Key (.pem)"
  type        = string
}

variable "region" {
  description = "OCI Region (e.g., ap-tokyo-1, us-ashburn-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID (use tenancy OCID for root compartment)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
}

variable "ssh_public_key_v2" {
  description = "SSH public key for replacement instance (ymatch-arm-v2)"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "availability_domain" {
  description = "Availability domain name (leave empty to use first available)"
  type        = string
  default     = ""
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the A1 instance (max 4 for free tier)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB for the A1 instance (max 24 for free tier)"
  type        = number
  default     = 12
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB (free tier: up to 200GB total)"
  type        = number
  default     = 50
}

variable "nr_license_key" {
  description = "New Relic Ingest License Key for Infrastructure agent"
  type        = string
  sensitive   = true
}

variable "nr_account_id" {
  description = "New Relic Account ID (for Flex integration)"
  type        = string
}

variable "alert_email" {
  description = "Email address for OCI budget alerts"
  type        = string
}
