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

# ---------------------------------------------------
# Networking (VPC & Connector for Cloud Run)
# ---------------------------------------------------
resource "google_compute_network" "default" {
  name = "ymatch-network"
}

resource "google_compute_subnetwork" "default" {
  name          = "ymatch-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.default.id
  region        = var.region
}

resource "google_vpc_access_connector" "connector" {
  name          = "ymatch-vpc-connector"
  region        = var.region
  network       = google_compute_network.default.name
  ip_cidr_range = "10.8.0.0/28"
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
      image = var.backend_image

      env {
        name  = "DATABASE_URL"
        value = "postgres://ymatch_user:${var.db_password}@${google_compute_instance.db_vm.network_interface[0].network_ip}:5432/ymatch_db"
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

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
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
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30 # 30GB standard persistent disk is free tier
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
    access_config {
      # Ephemeral public IP
    }
  }

  # Startup script to install docker and run postgres
  metadata_startup_script = <<EOF
#!/bin/bash
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

docker run -d \
  --name postgres \
  -e POSTGRES_USER=ymatch_user \
  -e POSTGRES_PASSWORD=${var.db_password} \
  -e POSTGRES_DB=ymatch_db \
  -p 5432:5432 \
  -v /var/lib/postgresql/data:/var/lib/postgresql/data \
  --restart unless-stopped \
  public.ecr.aws/docker/library/postgres:16-alpine
EOF

  tags = ["allow-postgres"]
}

# Allow internal traffic to the DB from the VPC and connector range
resource "google_compute_firewall" "allow_postgres_internal" {
  name    = "allow-postgres-internal"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Restricted to VPC and Connector internal ranges
  source_ranges = ["10.0.0.0/24", "10.8.0.0/28"]
  target_tags   = ["allow-postgres"]
}

# ---------------------------------------------------
# Firebase Hosting (Conceptual)
# ---------------------------------------------------
# Terraform support for Firebase is available but often managed via firebase-tools CLI.
# This section serves as a placeholder for the resources.

# resource "google_firebase_project" "default" {
#   provider = google-beta
#   project  = var.project_id
# }

# resource "google_firebase_hosting_site" "default" {
#   provider = google-beta
#   project  = var.project_id
#   site_id  = "ymatch-frontend"
# }
