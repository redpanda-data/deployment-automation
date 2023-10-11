variable "gcp_creds" {
  default     = ""
  description = "base64 encoded json GCP key file for a service account"
}

provider "google" {
  project     = var.project_name
  region      = var.region
  credentials = base64decode(var.gcp_creds)
}

variable "region" {
  type    = string
  default = "us-central1"
}
variable "public_key_path" {
  default = ""
  type    = string
}
module "redpanda-cluster" {
  source                     = "redpanda-data/redpanda-cluster/gcp"
  version                    = ">= 0.6.3"
  ssh_user                   = "ubuntu"
  subnet                     = google_compute_subnetwork.test-subnet.id
  region                     = var.region
  enable_tiered_storage      = true
  allow_force_destroy        = true
  allocate_brokers_public_ip = false
  public_key_path            = var.public_key_path
  deployment_prefix          = var.deployment_prefix
  hosts_file                 = var.hosts_file
  image                      = var.image
}

resource "google_compute_network" "test-net" {
  name                    = "${var.deployment_prefix}-proxy-net"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "test-subnet" {
  name          = "${var.deployment_prefix}-test-sub"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.test-net.self_link
}

resource "google_compute_firewall" "broker-broker" {
  name    = "${var.deployment_prefix}-allow-broker-to-broker"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_tags = ["broker"]
  target_tags = ["broker"]
}

resource "google_compute_firewall" "broker-to-client" {
  name    = "${var.deployment_prefix}-broker-to-client"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }

  source_tags = ["broker"]
  target_tags = ["client"]
}

resource "google_compute_firewall" "client-to-broker" {
  name    = "${var.deployment_prefix}-client-to-broker"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  target_tags = ["broker"]
  source_tags = ["client"]
}


resource "google_compute_firewall" "client-to-internet" {
  name    = "${var.deployment_prefix}-client-to-internet"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  source_tags        = ["client"]
  destination_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "internet-to-client" {
  name    = "${var.deployment_prefix}-internet-to-client"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "21", "20"]
  }
  target_tags   = ["client"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "internet-to-monitor" {
  name    = "${var.deployment_prefix}-internet-to-monitor"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  target_tags   = ["monitor"]
  source_ranges = ["0.0.0.0/0"]
}
resource "google_compute_firewall" "monitor-to-internet" {
  name    = "${var.deployment_prefix}-monitor-to-internet"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  source_tags        = ["monitor"]
  destination_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "monitor-to-broker" {
  name    = "${var.deployment_prefix}-monitor-to-broker"
  network = google_compute_network.test-net.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  target_tags = ["broker"]
  source_tags = ["monitor"]
}

variable "deployment_prefix" {
  type = string
}

variable "project_name" {
  default = ""
}

variable "hosts_file" {
  type = string
}

variable "image" {
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
  type    = string
}
