resource "random_uuid" "cluster" {}

locals {
  uuid = random_uuid.cluster.result
  deployment_id = "${random_uuid.cluster.result}"
}

resource "azurerm_resource_group" "redpanda" {
  name     = "redpanda_resources_${local.deployment_id}"
  location = var.region

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_proximity_placement_group" "redpanda" {
  name                = "redpanda_proximity_group"
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_availability_set" "redpanda" {
  name                         = "redpanda_availability_set_${local.deployment_id}"
  resource_group_name          = azurerm_resource_group.redpanda.name
  location                     = azurerm_resource_group.redpanda.location
  proximity_placement_group_id = azurerm_proximity_placement_group.redpanda.id
  count                        = var.ha ? 0 : 1

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_orchestrated_virtual_machine_scale_set" "redpanda" {
  name                         = "redpanda_scale_set_${local.deployment_id}"
  resource_group_name          = azurerm_resource_group.redpanda.name
  location                     = azurerm_resource_group.redpanda.location
  proximity_placement_group_id = azurerm_proximity_placement_group.redpanda.id
  platform_fault_domain_count  = 3
  count                        = var.ha ? 1 : 0

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_network_security_group" "redpanda" {
  name                = "redpanda_nsg"
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location

  security_rule {
    name                       = "ssh"
    description                = "SSH access to the VMs"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 100
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "redpanda_api"
    description                = "HTTP access to the Redpanda API port"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9092"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 101
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "redpanda_rpc"
    description                = "HTTP access to the Redpanda RPC port"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "33145"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 102
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "redpanda_admin"
    description                = "HTTP access to the Redpanda Admin port"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9644"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 103
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "redpanda_proxy"
    description                = "HTTP access to the Redpanda Proxy"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8082"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 104
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "redpanda_schema_registry"
    description                = "HTTP access to the Redpanda Schema Registry"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 105
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "grafana"
    description                = "HTTP access to Grafana"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 106
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "prometheus"
    description                = "HTTP access to Prometheus"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 107
    direction                  = "Inbound"
  }

  security_rule {
    name                       = "internet"
    description                = "Outbound internet access"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 108
    direction                  = "Outbound"
  }

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_virtual_network" "redpanda" {
  name                = "redpanda_vnet"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location
  
  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_subnet" "redpanda" {
  name                 = "redpanda_subnet"
  resource_group_name  = azurerm_resource_group.redpanda.name
  virtual_network_name = azurerm_virtual_network.redpanda.name
  address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "redpanda" {
  subnet_id                 = azurerm_subnet.redpanda.id
  network_security_group_id = azurerm_network_security_group.redpanda.id
}

#
# Network interfaces and IP addresses for the Redpanda broker(s)
#

resource "azurerm_public_ip" "redpanda" {
  name                = "redpanda_public_ip${count.index}"
  count               = var.vm_instances
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location
  allocation_method   = "Static"
  availability_zone   = try(var.zone, "Zone-Redundant")
  sku                 = "Standard"

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_network_interface" "redpanda" {
  name                          = "redpanda_nic${count.index}"
  count                         = var.vm_instances
  resource_group_name           = azurerm_resource_group.redpanda.name
  location                      = azurerm_resource_group.redpanda.location
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "ip_addresses"
    subnet_id                     = azurerm_subnet.redpanda.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.redpanda.*.id, count.index)}"
  }
}

resource "azurerm_network_interface_security_group_association" "redpanda" {
  count                     = var.vm_instances
  network_interface_id      = "${element(azurerm_network_interface.redpanda.*.id, count.index)}"
  network_security_group_id = azurerm_network_security_group.redpanda.id
}

#
# Network interfaces and IP addresses for the Redpanda client(s)
#

resource "azurerm_public_ip" "redpanda_client" {
  name                = "client_public_ip${count.index}"
  count               = var.client_vm_instances
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location
  allocation_method   = "Static"
  availability_zone   = try(var.zone, "Zone-Redundant")
  sku                 = "Standard"
  
  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_network_interface" "redpanda_client" {
  name                          = "client_nic${count.index}"
  count                         = var.client_vm_instances
  resource_group_name           = azurerm_resource_group.redpanda.name
  location                      = azurerm_resource_group.redpanda.location
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "ip_addresses"
    subnet_id                     = azurerm_subnet.redpanda.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.redpanda_client.*.id, count.index)}"
  }
}

resource "azurerm_network_interface_security_group_association" "redpanda_client" {
  count                     = var.client_vm_instances
  network_interface_id      = "${element(azurerm_network_interface.redpanda_client.*.id, count.index)}"
  network_security_group_id = azurerm_network_security_group.redpanda.id
}

#
# Network interface and IP addresse for the monitoring VM
#

resource "azurerm_public_ip" "monitoring" {
  name                = "monitoring_public_ip"
  count               = var.enable_monitoring ? 1 : 0
  resource_group_name = azurerm_resource_group.redpanda.name
  location            = azurerm_resource_group.redpanda.location
  allocation_method   = "Static"
  availability_zone   = try(var.zone, "Zone-Redundant")
  sku                 = "Standard"

  tags = {
    deployment_id = local.deployment_id
  }
}

resource "azurerm_network_interface" "monitoring" {
  name                          = "monitoring_nic"
  count                         = var.enable_monitoring ? 1 : 0
  resource_group_name           = azurerm_resource_group.redpanda.name
  location                      = azurerm_resource_group.redpanda.location
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "ip_addresses"
    subnet_id                     = azurerm_subnet.redpanda.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.monitoring.*.id, count.index)}"
  }
}

resource "azurerm_network_interface_security_group_association" "monitoring" {
  count                     = var.enable_monitoring ? 1 : 0
  network_interface_id      = "${element(azurerm_network_interface.monitoring.*.id, count.index)}"
  network_security_group_id = azurerm_network_security_group.redpanda.id
}
