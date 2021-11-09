#
# Redpanda broker VMs
#

resource "azurerm_linux_virtual_machine" "redpanda" {
  name                 = "redpanda_broker${count.index}"
  computer_name        = "redpanda${count.index}"
  count                = var.vm_instances
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  # availability_set_id  = azurerm_availability_set.redpanda.id
  size                 = var.vm_sku
  admin_username       = var.admin_username
  network_interface_ids = ["${element(azurerm_network_interface.redpanda.*.id, count.index)}"]
  zone = try(var.zone, null)

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # additional_capabilities {
  #   ultra_ssd_enabled = true
  # }
  
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key)
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_managed_disk" "redpanda" {
  name                 = "managed_disk${count.index}"
  count                = var.vm_add_data_disk ? var.vm_instances : 0
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  storage_account_type = "Premium_LRS"
  # storage_account_type = "UltraSSD_LRS"
  create_option        = "Empty"
  # https://docs.microsoft.com/en-us/azure/virtual-machines/disks-change-performance
  disk_size_gb         = var.vm_data_disk_gb

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "redpanda" {
  count                     = var.vm_add_data_disk ? var.vm_instances : 0
  managed_disk_id           = "${element(azurerm_managed_disk.redpanda.*.id, count.index)}"
  virtual_machine_id        = "${element(azurerm_linux_virtual_machine.redpanda.*.id, count.index)}"
  lun                       = "10"
  caching                   = "None"
  # Only available on M-series with Premium_LRS disks and no caching:
  write_accelerator_enabled = false
}

#
# Client VMs
#

resource "azurerm_linux_virtual_machine" "redpanda_client" {
  name                 = "redpanda_client${count.index}"
  computer_name        = "client${count.index}"
  count                = var.client_vm_instances
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  # availability_set_id  = azurerm_availability_set.redpanda.id
  size                 = var.client_vm_sku
  admin_username       = var.admin_username
  network_interface_ids = ["${element(azurerm_network_interface.redpanda_client.*.id, count.index)}"]

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key)
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  tags = {
    deployment_id = local.deployment_id
  }
}

#
# Monitoring VM
#

resource "azurerm_linux_virtual_machine" "monitoring" {
  name                 = "monitor"
  count                = var.enable_monitoring ? 1 : 0
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  # availability_set_id  = azurerm_availability_set.redpanda.id
  size                 = var.monitoring_vm_sku
  admin_username       = var.admin_username
  network_interface_ids = ["${element(azurerm_network_interface.monitoring.*.id, count.index)}"]

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key)
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  tags = {
    deployment_id = local.deployment_id
  }
}