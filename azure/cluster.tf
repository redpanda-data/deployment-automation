resource "azurerm_linux_virtual_machine" "redpanda" {
  name                 = "redpanda_broker${count.index}"
  computer_name        = "redpanda${count.index}"
  count                = var.vm_instances
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  availability_set_id  = azurerm_availability_set.redpanda.id
  size                 = var.vm_sku
  admin_username       = var.admin_username
  network_interface_ids = ["${element(azurerm_network_interface.redpanda.*.id, count.index)}"]

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

resource "azurerm_managed_disk" "redpanda" {
  name                 = "managed_disk${count.index}"
  count                = var.vm_instances
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "16"

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "redpanda" {
  count              = var.vm_instances
  managed_disk_id    = "${element(azurerm_managed_disk.redpanda.*.id, count.index)}"
  virtual_machine_id = "${element(azurerm_linux_virtual_machine.redpanda.*.id, count.index)}"
  lun                = "10"
  caching            = "None"
}

resource "azurerm_linux_virtual_machine" "redpanda_client" {
  name                 = "redpanda_client"
  computer_name        = "client${count.index}"
  count                = var.client_vm_instances
  resource_group_name  = azurerm_resource_group.redpanda.name
  location             = azurerm_resource_group.redpanda.location
  availability_set_id  = azurerm_availability_set.redpanda.id
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