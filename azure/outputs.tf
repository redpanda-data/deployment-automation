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

output "monitor_public_ip" {
  value = "${azurerm_public_ip.monitoring.*.ip_address}"
}

output "monitor_private_ip" {
  value = "${azurerm_network_interface.monitoring.*.private_ip_address}"
}

output "ssh_user" {
  value = var.admin_username
}

output "public_key_path" {
  value = var.public_key_path
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips        = "${azurerm_public_ip.redpanda.*.ip_address}"
      redpanda_private_ips       = "${azurerm_network_interface.redpanda.*.private_ip_address}"
      client_public_ips          = "${azurerm_public_ip.redpanda_client.*.ip_address}"
      client_private_ips         = "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
      monitor_public_ip          = var.enable_monitoring ? "${azurerm_public_ip.monitoring.0.ip_address}" : ""
      monitor_private_ip         = var.enable_monitoring ? "${azurerm_network_interface.monitoring.0.private_ip_address}" : ""
      enable_monitoring          = "${var.enable_monitoring}"
      ssh_user                   = "${var.admin_username}"
      rack                       = "${azurerm_linux_virtual_machine.redpanda.*.platform_fault_domain}"
      cloud_storage_region       = var.region
      tiered_storage_enabled     = false
      tiered_storage_bucket_name = ""
    }
  )
  filename = "${path.module}/../hosts.ini"
}
