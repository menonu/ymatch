terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The region to deploy resources to"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "The database password"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------
# Cloud Run (Backend)
# ---------------------------------------------------
resource "google_cloud_run_v2_service" "backend" {
  name     = "ymatch-backend"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" # Placeholder, update with actual image

      env {
        name  = "DATABASE_URL"
        # Reference the internal IP of the Compute Engine instance
        value = "postgres://ymatch_user:$${var.db_password}@$${google_compute_instance.db_vm.network_interface[0].network_ip}:5432/ymatch"
      }
      
      env {
        name  = "RUST_LOG"
        value = "info"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}

# Allow unauthenticated access to the backend
resource "google_cloud_run_v2_service_iam_member" "noauth" {
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------
# Compute Engine VM (Database - e2-micro Free Tier)
# ---------------------------------------------------
resource "google_compute_instance" "db_vm" {
  name         = "ymatch-db-vm"
  machine_type = "e2-micro"
  zone         = "$${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30 # 30GB standard persistent disk is free tier
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral public IP required for outbound internet access to download Docker/images unless Cloud NAT is configured
    }
  }

  # Startup script to install docker and run postgres
  metadata_startup_script = <<EOF
#!/bin/bash
apt-get update
apt-get install -y docker.io
docker run -d \
  --name postgres \
  -e POSTGRES_USER=ymatch_user \
  -e POSTGRES_PASSWORD=${var.db_password} \
  -e POSTGRES_DB=ymatch \
  -p 5432:5432 \
  -v /var/lib/postgresql/data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:16-alpine
EOF

  tags = ["allow-postgres"]
}

# Allow internal traffic to the DB from Cloud Run
resource "google_compute_firewall" "allow_postgres_internal" {
  name    = "allow-postgres-internal"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Replace with appropriate internal ranges depending on VPC setup
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] 
  target_tags   = ["allow-postgres"]
}
