variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone to deploy resources to"
  type        = string
  default     = "us-central1-a"
}

variable "db_password" {
  description = "The database password"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  description = "The Docker image for the backend"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}
