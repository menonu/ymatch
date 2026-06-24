output "instance_public_ip" {
  description = "Public IP of the production ymatch ARM instance (ymatch-arm-v2)"
  value       = oci_core_instance.ymatch_v2.public_ip
}

output "instance_id" {
  description = "OCID of the production compute instance"
  value       = oci_core_instance.ymatch_v2.id
}

output "ssh_command" {
  description = "SSH command to connect to the production instance"
  value       = "ssh -i <private_key> ubuntu@${oci_core_instance.ymatch_v2.public_ip}"
}

output "app_url" {
  description = "Production application URL (available after deploy script runs)"
  value       = "https://${oci_core_instance.ymatch_v2.public_ip}.nip.io"
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.ymatch.id
}

# Kept for backward compatibility with existing scripts/outputs consumers that
# referenced the v2 instance by these names.
output "instance_v2_public_ip" {
  description = "Public IP of the production instance (ymatch-arm-v2)"
  value       = oci_core_instance.ymatch_v2.public_ip
}

output "instance_v2_id" {
  description = "OCID of the production compute instance"
  value       = oci_core_instance.ymatch_v2.id
}

output "instance_staging_public_ip" {
  description = "Public IP of the dedicated staging instance (ymatch-arm-staging)"
  value       = oci_core_instance.ymatch_staging.public_ip
}

output "instance_staging_id" {
  description = "OCID of the staging compute instance"
  value       = oci_core_instance.ymatch_staging.id
}

output "staging_app_url" {
  description = "Staging application URL (available after deploy script runs)"
  value       = "https://${oci_core_instance.ymatch_staging.public_ip}.nip.io"
}
