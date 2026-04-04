variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-west1"
}

variable "billing_account" {
  description = "GCP Billing Account ID"
  type        = string
}
