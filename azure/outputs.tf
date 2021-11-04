output "redpanda_public_ips" {
  value = "${azurerm_public_ip.redpanda.*.ip_address}"
}

output "redpanda_private_ips" {
  value = "${azurerm_network_interface.redpanda.*.private_ip_address}"
}

output "client_public_ips" {
  value = "${azurerm_public_ip.redpanda_client.*.ip_address}"
}

output "client_private_ips" {
  value = "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
}

output "ssh_user" {
  value = var.admin_username
}

output "public_key_path" {
  value = var.public_key
}
