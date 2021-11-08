variable "region" {
  description = "Azure Region where the Resource Group will exist"
  default     = "North Europe"
}

variable "zone" {
  description = "Availability Zone"
  default     = null
}

variable "vm_sku" {
  description = "Azure VM SKU to use for the Redpanda nodes"
  default     = "Standard_L8s_v2" # Lsv2-series sizes have local NVMe disks
}

variable "vm_instances" {
  description = "Number of Redpanda nodes to create"
  type        = number
  default     = 3
}

variable "vm_add_data_disk" {
  description = "Attach a Premium_LRS data disk to each node?"
  type        = bool
  default     = false
}

variable "vm_data_disk_gb" {
  description = "Size of the Premium_LRS data disk in GiB"
  type        = number
  default     = 2048 #P50
}

variable "client_vm_sku" {
  description = "Azure VM SKU to use for the client node"
  default     = "Standard_D2s_v4"
}

variable "client_vm_instances" {
  description = "Number of client nodes to create"
  type        = number
  default     = 1
}

variable "vm_image" {
  description = "Source image reference for the VMs"
  type = object({
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

variable "public_key" {
  description = "Public Key file used for authentication"
  default     = "~/.ssh/id_rsa.pub"
}
