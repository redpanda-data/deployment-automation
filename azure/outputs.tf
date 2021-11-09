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

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips  = "${azurerm_public_ip.redpanda.*.ip_address}"
      redpanda_private_ips = "${azurerm_network_interface.redpanda.*.private_ip_address}"
      client_public_ips    = "${azurerm_public_ip.redpanda_client.*.ip_address}"
      client_private_ips   = "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
      monitor_public_ip    = "${azurerm_public_ip.monitoring.*.ip_address}"
      monitor_private_ip   = "${azurerm_network_interface.monitoring.*.private_ip_address}"
      enable_monitoring    = var.enable_monitoring
      ssh_user             = var.admin_username
    }
  )
  filename = "${path.module}/../hosts.ini"
}
