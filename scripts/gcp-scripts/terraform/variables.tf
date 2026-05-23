variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-central2-a"
}

variable "cluster_name" {
  description = "Prefix used to name all GCP resources"
  type        = string
}

variable "master_machine_type" {
  description = "GCP machine type for the master node"
  type        = string
  default     = "e2-standard-2"
}

variable "worker_machine_type" {
  description = "GCP machine type for worker nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for all nodes"
  type        = number
  default     = 50
}

variable "ssh_user" {
  description = "OS username injected via SSH key metadata"
  type        = string
}

variable "ssh_public_key" {
  description = "Full SSH public key string (e.g. 'ssh-rsa AAAA...')"
  type        = string
  sensitive   = true
}
