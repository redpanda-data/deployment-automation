locals {
  zone_count = try(length(var.availability_zone), 0)
  multi_az = local.zone_count > 1
  single_az = local.zone_count <= 1
  use_availability_sets = var.ha && local.single_az
  use_vmss = ! local.use_availability_sets
}

#
# Redpanda broker VMs
#

resource "azurerm_linux_virtual_machine" "redpanda" {
  name                         = "redpanda_broker${count.index}"
  computer_name                = "redpanda${count.index}"
  count                        = var.vm_instances
  resource_group_name          = azurerm_resource_group.redpanda.name
  location                     = azurerm_resource_group.redpanda.location
  availability_set_id          = local.use_availability_sets ? azurerm_availability_set.redpanda.0.id : null
  proximity_placement_group_id = local.single_az ? azurerm_proximity_placement_group.redpanda.0.id : null
  virtual_machine_scale_set_id = local.use_vmss ? azurerm_orchestrated_virtual_machine_scale_set.redpanda.0.id : null
  platform_fault_domain        = local.multi_az || local.use_availability_sets ? null : count.index % 3
  zone                         = local.use_availability_sets ? null : try(var.availability_zone[count.index % length(var.availability_zone)], null)
  size                         = var.vm_sku
  admin_username               = var.admin_username
  network_interface_ids        = ["${element(azurerm_network_interface.redpanda.*.id, count.index)}"]

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key_path)
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
  name                         = "redpanda_client${count.index}"
  computer_name                = "client${count.index}"
  count                        = var.client_vm_instances
  resource_group_name          = azurerm_resource_group.redpanda.name
  location                     = azurerm_resource_group.redpanda.location
  proximity_placement_group_id = local.single_az ? azurerm_proximity_placement_group.redpanda.0.id : null
  size                         = var.client_vm_sku
  admin_username               = var.admin_username
  network_interface_ids        = ["${element(azurerm_network_interface.redpanda_client.*.id, count.index)}"]
  zone                         = try(var.availability_zone[count.index % length(var.availability_zone)], null)

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key_path)
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
  name                         = "monitor"
  count                        = var.enable_monitoring ? 1 : 0
  resource_group_name          = azurerm_resource_group.redpanda.name
  location                     = azurerm_resource_group.redpanda.location
  proximity_placement_group_id = local.single_az ? azurerm_proximity_placement_group.redpanda[0].id : null
  size                         = var.monitoring_vm_sku
  admin_username               = var.admin_username
  network_interface_ids        = ["${element(azurerm_network_interface.monitoring.*.id, count.index)}"]

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key_path)
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
