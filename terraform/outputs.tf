output "backend_url" {
  value       = google_cloud_run_v2_service.backend.uri
  description = "The URL of the backend service"
}

output "db_vm_internal_ip" {
  value       = google_compute_instance.db_vm.network_interface[0].network_ip
  description = "The internal IP of the database VM"
}
