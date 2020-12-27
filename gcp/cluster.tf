provider "google" {
  credentials = file(pathexpand("~/.gcp.json"))
  project     = "vectorized"
  region      = var.region
  zone        = "${var.region}-${var.zone}"
}

resource "google_compute_instance" "redpanda" {
  count        = var.nodes
  name         = "rp-node-${count.index}"
  tags         = ["rp-node"]
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

resource "google_compute_instance" "prometheus" {
  count        = var.enable_monitoring ? 1 : 0
  name         = "rp-monitoring"
  tags         = ["rp-monitoring"]
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

resource "local_file" "hosts_ini" {
  content = templatefile("${path.module}/../templates/hosts_ini.tpl",
    {
      redpanda_public_ips   = google_compute_instance.redpanda.*.network_interface.0.access_config.0.nat_ip
      redpanda_private_ips  = google_compute_instance.redpanda.*.network_interface.0.network_ip
      prometheus_public_ip  = var.enable_monitoring ? google_compute_instance.prometheus[0].network_interface.0.access_config.0.nat_ip : ""
      prometheus_private_ip = var.enable_monitoring ? google_compute_instance.prometheus[0].network_interface.0.network_ip : ""
      ssh_user              = var.ssh_user
      enable_monitoring     = var.enable_monitoring
    }
  )
  filename = "${path.module}/../hosts.ini"
}
