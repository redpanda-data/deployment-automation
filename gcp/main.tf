variable "deployment_prefix" {
  type    = string
  default = "rp-test"
}

resource "google_compute_network" "test-net" {
  name                    = "${var.deployment_prefix}-test-net"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "test-subnet" {
  name          = "${var.deployment_prefix}-test-sub"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.test-net.self_link
}

resource "google_compute_firewall" "test-fire" {
  name    = "${var.deployment_prefix}-test-fire"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3000", "8888", "8889", "9090", "9092", "9100", "9644", "33145", "8081"]
  }

  source_ranges = ["0.0.0.0/0"]
}

module "redpanda-cluster" {
  source  = "redpanda-data/redpanda-cluster/gcp"
  version = ">= 0.6.3"
  region  = var.region

  ssh_user              = var.ssh_user
  subnet                = coalesce(var.subnet, google_compute_subnetwork.test-subnet.id)
  image                 = var.image
  availability_zone     = var.availability_zone
  broker_count          = var.nodes
  client_count          = var.client_nodes
  disks                 = var.disks
  ha                    = var.ha
  broker_machine_type   = var.machine_type
  client_machine_type   = var.client_machine_type
  monitor_machine_type  = var.monitor_machine_type
  public_key_path       = var.public_key_path
  enable_monitoring     = var.enable_monitoring
  labels                = var.labels
  deployment_prefix     = var.deployment_prefix
  hosts_file            = var.hosts_file
  enable_tiered_storage = var.tiered_storage_enabled
  allow_force_destroy   = true
}

provider "google" {
  region      = var.region
  project     = var.project_name
  credentials = base64decode(var.gcp_creds)
}

variable "gcp_creds" {
  default     = ""
  type        = string
  description = "base64 encoded contents of the key for a service account with all necessary permissions"
}

variable "region" {
  default = "us-west2"
}

variable "availability_zone" {
  description = "The zone where the cluster will be deployed [a,b,...]"
  default     = ["a"]
  type        = list(string)
}

variable "subnet" {
  description = "The name of the existing subnet where the machines will be deployed"
  default     = ""
}

variable "project_name" {
  default     = "hallowed-ray-376320"
  type        = string
  description = "The project name on GCP."
}

variable "nodes" {
  description = "The number of nodes to deploy."
  type        = number
  default     = "3"
}

variable "ha" {
  description = "Whether to use placement groups to create an HA topology"
  type        = bool
  default     = false
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
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
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
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_user" {
  description = "The ssh user. Must match the one in the public ssh key's comments."
  default     = "ubuntu"
  type        = string
}

variable "enable_monitoring" {
  default = true
}

variable "labels" {
  description = "passthrough of GCP labels"
  default     = {
    "purpose"      = "redpanda-cluster"
    "created-with" = "terraform"
  }
}

variable "hosts_file" {
  type        = string
  description = "location of ansible hosts file"
  default     = "../hosts.ini"
}

variable "tiered_storage_enabled" {
  default = false
  type    = bool
}
