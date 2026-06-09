terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ---------------------------------------------------
# Networking
# ---------------------------------------------------
resource "oci_core_vcn" "ymatch" {
  compartment_id = var.compartment_ocid
  display_name   = "ymatch-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "ymatch"
}

resource "oci_core_internet_gateway" "ymatch" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch.id
  display_name   = "ymatch-igw"
  enabled        = true
}

resource "oci_core_route_table" "ymatch" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch.id
  display_name   = "ymatch-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.ymatch.id
  }
}

resource "oci_core_security_list" "ymatch" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch.id
  display_name   = "ymatch-sl"

  # Allow all outbound
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS (Production)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Staging HTTP
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 8080
      max = 8080
    }
  }

  # Staging HTTPS
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 8443
      max = 8443
    }
  }

  # ICMP (ping) for diagnostics
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "10.0.0.0/16"
    icmp_options {
      type = 3
    }
  }
}

resource "oci_core_subnet" "ymatch" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.ymatch.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "ymatch-subnet"
  dns_label         = "ymatchsub"
  route_table_id    = oci_core_route_table.ymatch.id
  security_list_ids = [oci_core_security_list.ymatch.id]
}

# ---------------------------------------------------
# Compute (ARM Ampere A1 — Always Free)
# ---------------------------------------------------
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "ymatch" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "ymatch-arm"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.ymatch.id
    assign_public_ip = true
    display_name     = "ymatch-vnic"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [metadata, source_details]
  }
}

resource "oci_core_instance" "ymatch_v2" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "ymatch-arm-v2"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.ymatch.id
    assign_public_ip = true
    display_name     = "ymatch-vnic-v2"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key_v2
    user_data           = base64encode(local.cloud_init)
  }

  lifecycle {
    ignore_changes = [metadata, source_details]
  }
}

locals {
  cloud_init = <<-EOT
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/ymatch-setup.log 2>&1

    echo "=== ymatch OCI setup starting at $(date) ==="

    # Wait for any existing apt processes to finish
    while fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
      echo "Waiting for apt lock..."
      sleep 5
    done

    # Update and install prerequisites
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
      ca-certificates curl gnupg lsb-release \
      git

    # Install Docker (official method for Ubuntu ARM64)
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Add ubuntu user to docker group
    usermod -aG docker ubuntu

    # Open ports in iptables (OCI Ubuntu images have restrictive iptables by default)
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8080 -j ACCEPT
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8443 -j ACCEPT

    # Persist iptables rules (works on both 22.04 and 24.04)
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save
    else
      apt-get install -y iptables-persistent
      netfilter-persistent save
    fi

    # ---------------------------------------------------
    # New Relic Infrastructure Agent
    # ---------------------------------------------------
    echo "license_key: ${var.nr_license_key}" > /etc/newrelic-infra.yml
    echo "display_name: ${var.nr_display_name}" >> /etc/newrelic-infra.yml

    curl -fsSL https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/newrelic-infra.gpg --yes
    echo "deb [arch=arm64] https://download.newrelic.com/infrastructure_agent/linux/apt noble main" \
      | tee /etc/apt/sources.list.d/newrelic-infra.list > /dev/null
    apt-get update -qq
    apt-get install -y -qq newrelic-infra

    # Docker integration
    mkdir -p /etc/newrelic-infra/integrations.d
    cat > /etc/newrelic-infra/integrations.d/docker-config.yml <<'DCONF'
    integrations:
      - name: nri-docker
        interval: 30s
    DCONF

    # Replace `MemoryLimit=` (deprecated since systemd v243) with
    # `MemoryMax=` in the NR agent's systemd unit. Without this,
    # journal logs a deprecation warning on every boot, and a future
    # systemd release will silently ignore MemoryLimit, leaving the
    # agent with no memory cap. See issue #155.
    sed -i 's/^MemoryLimit=/MemoryMax=/' /etc/systemd/system/newrelic-infra.service
    sed -i '/^# MemoryMax=/d' /etc/systemd/system/newrelic-infra.service
    systemctl daemon-reload
    systemctl restart newrelic-infra

    # NOTE: OCI CLI and OCI billing Flex integration were removed from cloud-init
    # because pip install of oci-cli fails on this image (urllib3 conflict),
    # which causes the entire cloud-init script to abort. OCI billing data
    # is now collected via local cron on a machine that has OCI CLI installed
    # (see scripts/oci_cost_to_newrelic.sh). See issue #140.

    systemctl restart newrelic-infra

    echo "=== ymatch OCI setup complete at $(date) ==="
    echo "SSH in and run: cd ~/ymatch && ./scripts/oci_deploy.sh"
  EOT
}
