provider "google" {
  project     = var.project_name
  region      = var.region
  zone        = "${var.region}-${var.zone}"
}

resource "random_uuid" "cluster" {}

locals {
  uuid = random_uuid.cluster.result
  deployment_id = "${random_uuid.cluster.result}"
}

resource "google_compute_instance" "redpanda" {
  count        = var.nodes
  name         = "rp-node-${count.index}-${local.deployment_id}"
  tags         = ["rp-cluster", "tf-deployment-${local.deployment_id}"]
  machine_type = var.machine_type

  metadata = {
    ssh-keys = <<KEYS
${var.ssh_user}:${file(abspath(var.public_key_path))}
KEYS
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  dynamic "scratch_disk" {
    for_each = range(var.disks)
    content {
      // 375 GB local SSD drive.
      interface = "NVME"
    }
  }

  network_interface {
    subnetwork = var.subnet
    access_config {
    }
  }

}

resource "google_compute_instance" "monitor" {
  count        = 1
  name         = "rp-monitor-${local.deployment_id}"
  tags         = ["rp-cluster", "tf-deployment-${local.deployment_id}"]
  machine_type = var.monitor_machine_type

  metadata = {
    ssh-keys = <<KEYS
${var.ssh_user}:${file(abspath(var.public_key_path))}
KEYS
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  scratch_disk {
    // 375 GB local SSD drive.
    interface = "NVME"
  }

  network_interface {
    subnetwork = var.subnet
    access_config {
    }
  }

}

resource "google_compute_instance" "client" {
  count        = var.client_nodes
  name         = "rp-client-${count.index}-${local.deployment_id}"
  tags         = ["rp-cluster", "tf-deployment-${local.deployment_id}"]
  machine_type = var.client_machine_type

  metadata = {
    ssh-keys = <<KEYS
${var.ssh_user}:${file(abspath(var.public_key_path))}
KEYS
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  scratch_disk {
    // 375 GB local SSD drive.
    interface = "NVME"
  }

  network_interface {
    subnetwork = var.subnet
    access_config {
    }
  }
}

resource "google_compute_instance_group" "redpanda" {
  name      = "redpanda-group-${local.deployment_id}"
  zone      = "${var.region}-${var.zone}"
  instances = "${concat(google_compute_instance.redpanda.*.self_link,
                        google_compute_instance.client.*.self_link,
                        [google_compute_instance.monitor[0].self_link])}"
}

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips  = google_compute_instance.redpanda.*.network_interface.0.access_config.0.nat_ip
      redpanda_private_ips = google_compute_instance.redpanda.*.network_interface.0.network_ip
      client_public_ips    = google_compute_instance.client.*.network_interface.0.access_config.0.nat_ip
      client_private_ips   = google_compute_instance.client.*.network_interface.0.network_ip
      monitor_public_ip    = google_compute_instance.monitor[0].network_interface.0.access_config.0.nat_ip
      monitor_private_ip   = google_compute_instance.monitor[0].network_interface.0.network_ip
      ssh_user             = var.ssh_user
      enable_monitoring    = true
    }
  )
  filename = "${path.module}/../hosts.ini"
}
