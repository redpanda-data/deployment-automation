provider "google" {
  project     = var.project_name
  region      = var.region
  zone        = "${var.region}-${var.zone}"
}
