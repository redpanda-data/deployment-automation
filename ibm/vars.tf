variable "ssh_key" {}

variable "ibmcloud_api_key" {
  sensitive = true
}
variable "ssh_username" {
  description = "Username for the local administrator on each VM"
  default     = "ubuntu"
}
variable "enable_monitoring" {
    description = "Setup a prometheus/grafana instance"
    default = true
}

variable "number_of_instances" {
    description = "Number of VMs, IPs, and associated volume attachements"
    type = number
    default  = 3
}

variable "resource_group" {
    description = "Associated Resource Group"
    type = string
}

variable "base_name" {
    description = "Base name for the project. All subsequent resources are based on this."
    type = string
    default = "rp-project"
}

variable "region" {
    description = "IBM Cloud Zone where the project will instantiate."
    type = string
    default = "ca-tor"
}

variable "zone" {
    description = "IBM Cloud Zone where the project will instantiate."
    type = string
    default = "ca-tor-1"
}