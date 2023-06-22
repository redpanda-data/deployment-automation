variable "region" {
  description = "Azure Region where the Resource Group will exist"
  default     = "centralus"
}

variable "availability_zone" {
  description = "Availability Zones to deploy to - this can either be null or an array of zones"
  default     = null
  type        = list(string)
}

variable "network_range" {
  description = "CIDR range for Redpanda Network"
  default     = "10.0.0.0/16"
}

variable "subnet_range" {
  description = "CIDR range for Redpanda Subnet - should exist within the network range"
  default     = "10.0.1.0/24"
}

variable "vm_sku" {
  description = "Azure VM SKU to use for the Redpanda nodes"
  default     = "Standard_L8s_v3" # Lsv3-series sizes have local NVMe disks
}

variable "vm_public_networking" {
  description = "Create a public IP for each Redpanda node?"
  type        = bool
  default     = true
}

variable "vm_instances" {
  description = "Number of Redpanda nodes to create"
  type        = number
  default     = 3
}

variable "ha" {
  description = "Whether to use a scale set to enable rack awareness - this is ignored if any availability zones are specified"
  type        = bool
  default     = false
}

variable "vm_add_data_disk" {
  description = "Attach a Premium_LRS data disk to each node?"
  type        = bool
  default     = false
}

variable "vm_data_disk_gb" {
  description = "Size of the Premium_LRS data disk in GiB"
  type        = number
  default     = 2048 #P40
}

variable "client_vm_sku" {
  description = "Azure VM SKU to use for the client node"
  default     = "Standard_D2ds_v5"
  # Note when benchmark testing to match the max network
  # bandwidth with the Redpanda nodes.
}

variable "client_vm_public_networking" {
  description = "Create a public IP for each client node?"
  type        = bool
  default     = true
}

variable "client_vm_instances" {
  description = "Number of client nodes to create"
  type        = number
  default     = 0
}

variable "enable_monitoring" {
  description = "Setup a Prometheus/Grafana instance?"
  type        = bool
  default     = true
}

variable "monitoring_vm_sku" {
  description = "Azure VM SKU to use for the monitoring node"
  default     = "Standard_D2ds_v5"
}

variable "monitoring_vm_public_networking" {
  description = "Create a public IP for the monitoring node?"
  type        = bool
  default     = true
}

variable "vm_image" {
  description = "Source image reference for the VMs"
  type        = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  # Ubuntu 20.04 LTS
  # https://github.com/Azure/azure-cli/issues/13320#issuecomment-649867249
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}

variable "admin_username" {
  description = "Username for the local administrator on each VM"
  default     = "adminpanda"
}

variable "public_key_path" {
  description = "Public Key file used for authentication (must be RSA key on Azure)"
  default     = "~/.ssh/id_rsa.pub"
}
