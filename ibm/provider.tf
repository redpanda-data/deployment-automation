terraform {

    backend "s3" {
        bucket                      = "bts-terraform-state"
        key                         = "terraform.tfstate"
        region                      = "ca-tor"
        skip_region_validation      = true
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        endpoint                    = "https://s3.us-east.cloud-object-storage.appdomain.cloud"
    }

    required_providers {
        ibm = {
        source = "IBM-Cloud/ibm"
        version = "1.37.1"       
        }
    }
}

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

