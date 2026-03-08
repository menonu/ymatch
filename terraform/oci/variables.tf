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
  description = "Path to OCI API Private Key"
  type        = string
}

variable "region" {
  description = "OCI Region (e.g., us-ashburn-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID where resources will be created"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instance"
  type        = string
}

variable "db_password" {
  description = "Database password for Postgres"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  description = "Docker image for the Rust Axum backend"
  type        = string
  default     = "ghcr.io/yourusername/ymatch-backend:latest"
}
