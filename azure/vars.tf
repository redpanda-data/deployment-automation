variable "region" {
  description = "Azure Region where the Resource Group will exist"
  default     = "North Europe"
}

variable "vm_sku" {
  description = "Azure VM SKU to use for the Redpanda nodes"
  default     = "Standard_L8s_v2"
}

variable "vm_instances" {
  description = "Number of Redpanda nodes to create"
  type        = number
  default     = 3
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
  default = {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
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
