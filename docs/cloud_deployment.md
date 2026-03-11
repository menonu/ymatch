# Cloud Deployment Strategy

This document outlines the strategy for deploying the `ymatch` platform to the cloud, focusing on cost-efficiency using Free Tier services.

## Primary Target: Google Cloud Platform (GCP)

We have selected GCP as the primary deployment target due to its robust Free Tier offerings and ease of use for containerized applications.

### Architecture

- **Frontend**: [Firebase Hosting](https://firebase.google.com/docs/hosting)
  - Provides a fast and secure way to host the Flutter web application.
  - Generous free tier for storage and bandwidth.
- **Backend**: [Google Cloud Run](https://cloud.google.com/run)
  - Fully managed compute platform that automatically scales your stateless containers.
  - "Pay-as-you-go" model with a generous free tier (first 2 million requests per month).
- **Database**: [Google Compute Engine (GCE)](https://cloud.google.com/compute)
  - An `e2-micro` VM instance (Always Free tier).
  - Runs a PostgreSQL container using Docker.
  - 30GB of Standard Persistent Disk is included in the free tier.

## Secondary Target: Oracle Cloud Infrastructure (OCI)

OCI offers an exceptionally generous "Always Free" tier that we may investigate for future use or as a fallback.

### OCI Benefits

- **Compute**: Up to 4 ARM Ampere A1 Compute instances with 24 GB of RAM.
- **Compute**: 2 AMD-based Compute VMs.
- **Storage**: 200 GB of Block Storage.
- **Database**: Oracle Autonomous Database.

### Adaptation Strategy

The Terraform configurations are structured to be modular. While the current focus is GCP, the logic can be adapted to OCI by:
1. Creating OCI-specific Terraform modules.
2. Mapping the containerized backend to OCI Container Instances or a VM.
3. Using an OCI Compute VM or Autonomous Database for the PostgreSQL requirement.

## Deployment Process (GCP)

Detailed instructions for deploying to GCP will be added here as the infrastructure code is finalized.

1. **Initialize Terraform**: `cd terraform && terraform init`
2. **Apply Configuration**: `terraform apply`
3. **Build and Push Images**: Build the production Docker images and push them to Google Artifact Registry.
4. **Deploy to Cloud Run**: Update the Cloud Run service with the new image.
5. **Deploy to Firebase**: Run `firebase deploy` to upload the frontend assets.
