variable "region" {
  default = "us-west1"
}

variable "zone" {
  description = "The zone where the cluster will be deployed [a,b,...]"
  default     = "a"
}

variable "instance_group_name" {
  description = "The name of the GCP instance group"
  default     = "redpanda-group"  
}

variable "subnet" {
  description = "The name of the existing subnet where the machines will be deployed"
}

variable "project_name" {
  description = "The project name on GCP."
}

variable "nodes" {
  description = "The number of nodes to deploy."
  type        = number
  default     = "1"
}

variable "client_nodes" {
  description = "The number of clients to deploy."
  type        = number
  default     = "1"
}

variable "disks" {
  description = "The number of local disks on each machine."
  type        = number
  default     = 1
}

variable "image" {
  # See https://cloud.google.com/compute/docs/images#os-compute-support
  # for an updated list.
  default = "ubuntu-os-cloud/ubuntu-2004-lts"
}

variable machine_type {
  # List of available machines per region/ zone:
  # https://cloud.google.com/compute/docs/regions-zones#available
  default = "n2-standard-2"
}

variable monitor_machine_type {
  default = "n2-standard-2"
}

variable client_machine_type {
  default = "n2-standard-2"
}

variable "public_key_path" {
  description = "The ssh key."
}

variable "ssh_user" {
  description = "The ssh user. Must match the one in the public ssh key's comments."
}
