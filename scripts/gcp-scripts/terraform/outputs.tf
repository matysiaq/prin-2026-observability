output "master_public_ip" {
  description = "External IP of the master node"
  value       = google_compute_address.master.address
}

output "master_internal_ip" {
  description = "Internal IP of the master node"
  value       = google_compute_instance.master.network_interface[0].network_ip
}

output "worker_public_ips" {
  description = "External IPs of the worker nodes"
  value       = google_compute_address.worker[*].address
}

output "worker_internal_ips" {
  description = "Internal IPs of the worker nodes"
  value       = google_compute_instance.worker[*].network_interface[0].network_ip
}
