# Deploying ymatch to Oracle Cloud Infrastructure (OCI) Always Free Tier

Oracle Cloud Infrastructure (OCI) provides an exceptionally generous "Always Free" tier, including up to 4 ARM Ampere A1 Compute instances with 24GB of RAM. This makes it an excellent choice for hosting the entire ymatch stack (Flutter Web, Rust Axum backend, and PostgreSQL database) without incurring monthly cloud costs.

This guide explains how to use the provided Terraform configuration to provision the necessary OCI resources and deploy the application.

## Prerequisites

Before running the Terraform scripts, you need to set up your OCI account and gather some information:

1. **OCI Account:** Sign up for an [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/) account.
2. **OCI CLI and API Key:**
   - Install the [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm).
   - Generate an API signing key pair and upload the public key to your OCI user account.
   - Note the `Fingerprint` and the path to your `Private Key`.
3. **OCIDs (Oracle Cloud Identifiers):** You will need the following OCIDs:
   - **Tenancy OCID:** Found in the OCI Console under Profile -> Tenancy.
   - **User OCID:** Found under Identity & Security -> Users -> User Details.
   - **Compartment OCID:** Found under Identity & Security -> Compartments. (You can use the root compartment or create a new one).
4. **SSH Key Pair:** Generate an SSH key pair (`ssh-keygen -t rsa -b 2048`) to access the provisioned VM. You will need the path to the public key (`~/.ssh/id_rsa.pub`).
5. **Terraform:** Ensure [Terraform](https://developer.hashicorp.com/terraform/downloads) is installed on your local machine.

## Configuration

1. Navigate to the `terraform/oci` directory:
   ```bash
   cd terraform/oci
   ```

2. Create a `terraform.tfvars` file to store your variables. **Do not commit this file to version control.**
   ```bash
   touch terraform.tfvars
   ```

3. Populate `terraform.tfvars` with your OCI details:
   ```hcl
   tenancy_ocid     = "ocid1.tenancy.oc1..xxxx"
   user_ocid        = "ocid1.user.oc1..xxxx"
   fingerprint      = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
   private_key_path = "/path/to/your/oci_api_key.pem"
   region           = "us-ashburn-1" # e.g., us-ashburn-1, uk-london-1
   compartment_ocid = "ocid1.compartment.oc1..xxxx"
   ssh_public_key   = "ssh-rsa AAAA..." # The contents of your id_rsa.pub file
   db_password      = "YourSecureDatabasePassword"
   backend_image    = "ghcr.io/yourusername/ymatch-backend:latest" # Update with your image
   ```

## Deployment Steps

1. **Initialize Terraform:** Download the required provider plugins.
   ```bash
   terraform init
   ```

2. **Review the Plan:** See what resources Terraform will create.
   ```bash
   terraform plan
   ```

3. **Apply the Configuration:** Provision the infrastructure. Type `yes` when prompted.
   ```bash
   terraform apply
   ```

## What Terraform Does

The Terraform script performs the following actions:

1. **Networking:** Creates a Virtual Cloud Network (VCN), Internet Gateway, Route Table, and Subnet.
2. **Security:** Configures a Security List to allow inbound traffic on ports 22 (SSH), 80 (HTTP), 443 (HTTPS), and 3000 (Backend API).
3. **Compute Instance:** Provisions an Always Free `VM.Standard.A1.Flex` instance with 4 OCPUs and 24GB of RAM using Canonical Ubuntu 22.04 (ARM64).
4. **Provisioning (cloud-init):**
   - Updates the OS packages.
   - Installs Docker and Docker Compose.
   - Starts a PostgreSQL database container.
   - Starts the Rust Axum backend container.

## Accessing the Instance

Once deployment is complete, Terraform will output the public IP address of the newly created VM (you may need to add an output variable for this in `main.tf` if you want it displayed automatically, or find it in the OCI console).

You can SSH into the instance using the private key associated with the public key you provided:
```bash
ssh -i /path/to/your/private_key ubuntu@<public-ip-address>
```

## Next Steps

- **Frontend Deployment:** The current setup deploys the backend and database. You can host the Flutter web frontend directly on this same instance (using Nginx or Caddy) or use a static site hosting service like Cloudflare Pages or Firebase Hosting.
- **Domain Name and SSL:** Configure a domain name to point to your instance's public IP and set up an SSL certificate (e.g., using Let's Encrypt and a reverse proxy).
