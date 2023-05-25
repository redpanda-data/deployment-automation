output "redpanda_public_ips" {
  value = var.vm_public_networking ? "${azurerm_public_ip.redpanda.*.ip_address}" : "${azurerm_network_interface.redpanda.*.private_ip_address}"
}

output "redpanda_private_ips" {
  value = "${azurerm_network_interface.redpanda.*.private_ip_address}"
}

output "client_public_ips" {
  value = var.client_vm_public_networking ? "${azurerm_public_ip.redpanda_client.*.ip_address}" : "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
}

output "client_private_ips" {
  value = "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
}

output "monitor_public_ip" {
  value = var.monitoring_vm_public_networking ? "${azurerm_public_ip.monitoring.*.ip_address}" : "${azurerm_network_interface.monitoring.*.private_ip_address}"
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
      redpanda_public_ips        = var.vm_public_networking ? "${azurerm_public_ip.redpanda.*.ip_address}" : "${azurerm_network_interface.redpanda.*.private_ip_address}"
      redpanda_private_ips       = "${azurerm_network_interface.redpanda.*.private_ip_address}"
      client_public_ips          = var.client_vm_public_networking ? "${azurerm_public_ip.redpanda_client.*.ip_address}" : "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
      client_private_ips         = "${azurerm_network_interface.redpanda_client.*.private_ip_address}"
      monitor_public_ip          = var.enable_monitoring ? (var.monitoring_vm_public_networking ? "${element(azurerm_public_ip.monitoring.*.ip_address, 0)}" : "${element(azurerm_network_interface.monitoring.*.private_ip_address, 0)}") : ""
      monitor_private_ip         = var.enable_monitoring ? "${azurerm_network_interface.monitoring.0.private_ip_address}" : ""
      enable_monitoring          = "${var.enable_monitoring}"
      ssh_user                   = "${var.admin_username}"
      rack                       = local.zone_count < 2 ? azurerm_linux_virtual_machine.redpanda.*.platform_fault_domain : azurerm_linux_virtual_machine.redpanda.*.zone
      rack_awareness             = var.ha || local.multi_az
      cloud_storage_region       = var.region
      tiered_storage_enabled     = false
      tiered_storage_bucket_name = ""
    }
  )
  filename = "${path.module}/../hosts.ini"
}
