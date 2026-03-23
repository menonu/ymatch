variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "The zone to deploy resources to"
  type        = string
  default     = "us-west1-b"
}

variable "db_password" {
  description = "The database password"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  description = "The Docker image for the backend"
  type        = string
  default     = "us-central1-docker.pkg.dev/tangential-map-491113-b4/ymatch-repo/ymatch-backend:latest"
}
