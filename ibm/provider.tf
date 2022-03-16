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

provider "ibm" {
    ibmcloud_api_key = var.ibmcloud_api_key
    region = var.region
}
