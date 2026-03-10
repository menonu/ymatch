terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
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

# Network setup (VCN, Subnet, Internet Gateway, Route Table, Security List)
resource "oci_core_vcn" "ymatch_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "ymatch-vcn"
  cidr_block     = "10.0.0.0/16"
}

resource "oci_core_internet_gateway" "ymatch_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch_vcn.id
  display_name   = "ymatch-igw"
  enabled        = true
}

resource "oci_core_route_table" "ymatch_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch_vcn.id
  display_name   = "ymatch-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.ymatch_igw.id
  }
}

resource "oci_core_security_list" "ymatch_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ymatch_vcn.id
  display_name   = "ymatch-security-list"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      max = 22
      min = 22
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      max = 80
      min = 80
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      max = 443
      min = 443
    }
  }

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      max = 3000 # Backend port
      min = 3000
    }
  }
}

resource "oci_core_subnet" "ymatch_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.ymatch_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "ymatch-subnet"
  route_table_id    = oci_core_route_table.ymatch_rt.id
  security_list_ids = [oci_core_security_list.ymatch_sl.id]
}

# Data source for Canonical Ubuntu 22.04 aarch64
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Data source for Availability Domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

resource "oci_core_instance" "ymatch_instance" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "ymatch-a1-instance"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.ymatch_subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
    # Always Free requires boot volume size <= 200GB.
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }
}

locals {
  cloud_init = <<-EOT
    #!/bin/bash
    
    # Update packages
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    
    # Install Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Ensure Docker starts on boot
    systemctl enable docker
    systemctl start docker

    # Allow ports through local firewall
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
    iptables -I INPUT 6 -m state --state NEW -p tcp --dport 3000 -j ACCEPT
    netfilter-persistent save

    # Start Postgres Database
    docker run -d \
      --name postgres \
      --restart unless-stopped \
      -e POSTGRES_USER=ymatch_user \
      -e POSTGRES_PASSWORD=${var.db_password} \
      -e POSTGRES_DB=ymatch \
      -p 5432:5432 \
      -v pg_data:/var/lib/postgresql/data \
      postgres:16-alpine
      
    # Wait for postgres to be ready
    sleep 10
      
    # Run the backend
    # You might need to update this command to run your specific backend image 
    # and provide the necessary environment variables.
    docker run -d \
      --name backend \
      --restart unless-stopped \
      --network host \
      -e DATABASE_URL="postgres://ymatch_user:${var.db_password}@localhost:5432/ymatch" \
      -p 3000:3000 \
      ${var.backend_image}
  EOT
}
