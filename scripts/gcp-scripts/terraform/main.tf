# ──────────────────────────────────────────────────────────────────────────────
# Network
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_network" "k8s" {
  name                    = "${var.cluster_name}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k8s" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.k8s.id
}

# ──────────────────────────────────────────────────────────────────────────────
# Firewall — allow everything (workshop simplicity, not for production)
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_all" {
  name    = "${var.cluster_name}-allow-all"
  network = google_compute_network.k8s.name

  allow {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# ──────────────────────────────────────────────────────────────────────────────
# Master node — e2-standard-2 (2 vCPU, 8 GB RAM) — control plane only
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_address" "master" {
  name   = "${var.cluster_name}-master-ip"
  region = var.region
}

resource "google_compute_instance" "master" {
  name         = "${var.cluster_name}-master"
  machine_type = var.master_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s.id
    access_config {
      nat_ip = google_compute_address.master.address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Worker nodes — e2-standard-2 (2 vCPU, 8 GB RAM) each
# ──────────────────────────────────────────────────────────────────────────────

resource "google_compute_address" "worker" {
  count  = var.worker_count
  name   = "${var.cluster_name}-worker-${count.index + 1}-ip"
  region = var.region
}

resource "google_compute_instance" "worker" {
  count        = var.worker_count
  name         = "${var.cluster_name}-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s.id
    access_config {
      nat_ip = google_compute_address.worker[count.index].address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }
}
