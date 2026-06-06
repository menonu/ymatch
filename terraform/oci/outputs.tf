output "instance_public_ip" {
  description = "Public IP of the ymatch ARM instance"
  value       = oci_core_instance.ymatch.public_ip
}

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.ymatch.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i <private_key> ubuntu@${oci_core_instance.ymatch.public_ip}"
}

output "app_url" {
  description = "Application URL (available after deploy script runs)"
  value       = "https://${oci_core_instance.ymatch.public_ip}.nip.io"
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.ymatch.id
}

output "instance_v2_public_ip" {
  description = "Public IP of the replacement instance (ymatch-arm-v2)"
  value       = oci_core_instance.ymatch_v2.public_ip
}

output "instance_v2_id" {
  description = "OCID of the replacement compute instance"
  value       = oci_core_instance.ymatch_v2.id
}
