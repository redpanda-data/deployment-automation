output "ip" {
  value = google_compute_instance.redpanda.*.network_interface.0.access_config.0.nat_ip
}

output "private_ips" {
  value = google_compute_instance.redpanda.*.network_interface.0.network_ip
}

output "ssh_user" {
  value = var.ssh_user
}

output "public_key_path" {
  value = var.public_key_path
}
