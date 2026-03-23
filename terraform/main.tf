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
# Networking (VPC with Direct VPC Egress - no connector needed)
# ---------------------------------------------------
resource "google_compute_network" "default" {
  name                    = "ymatch-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "default" {
  name          = "ymatch-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.default.id
  region        = var.region
}

# ---------------------------------------------------
# Cloud Run (Backend) - uses Direct VPC Egress (free, no connector VMs)
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
      network_interfaces {
        network    = google_compute_network.default.id
        subnetwork = google_compute_subnetwork.default.id
      }
      egress = "PRIVATE_RANGES_ONLY"
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

  lifecycle {
    ignore_changes = [metadata_startup_script, network_interface]
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.default.id
    subnetwork = google_compute_subnetwork.default.id
    # No access_config — no external IPv4 (saves ~$3.60/month)
    # SSH via: gcloud compute ssh ymatch-db-vm --zone us-west1-b --tunnel-through-iap
    # To temporarily add external IP for maintenance:
    #   gcloud compute instances add-access-config ymatch-db-vm --zone us-west1-b
    # To remove after:
    #   gcloud compute instances delete-access-config ymatch-db-vm --zone us-west1-b --access-config-name external-nat
  }

  # Startup script: idempotent — safe to run on reboot without internet
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # If Docker is already installed, just ensure postgres is running
    if command -v docker &> /dev/null; then
      if ! docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
        docker start postgres 2>/dev/null || \
        docker run -d \
          --name postgres \
          -e POSTGRES_USER=ymatch_user \
          -e POSTGRES_PASSWORD=${var.db_password} \
          -e POSTGRES_DB=ymatch_db \
          -p 5432:5432 \
          -v /var/lib/postgresql/data:/var/lib/postgresql/data \
          --restart unless-stopped \
          postgres:16-alpine
      fi
      exit 0
    fi

    # First-time setup: requires internet (external IP must be temporarily enabled)
    set -e
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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
      postgres:16-alpine
  EOF

  tags = ["allow-postgres"]
}

# Allow DB traffic from the VPC subnet (Cloud Run Direct VPC Egress uses subnet IPs)
resource "google_compute_firewall" "allow_postgres_internal" {
  name    = "allow-postgres-internal"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["allow-postgres"]
}

# Allow SSH via IAP tunnel only (no external IP needed)
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "allow-ssh-iap"
  network = google_compute_network.default.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}
