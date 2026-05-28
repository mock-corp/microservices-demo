# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Definition of local variables
locals {
  base_apis = [
    "container.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com"
  ]
  memorystore_apis = ["redis.googleapis.com"]
  cluster_name     = google_container_cluster.my_cluster.name
}

# Enable Google Cloud APIs
module "enable_google_apis" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 18.0"

  project_id                  = var.gcp_project_id
  disable_services_on_destroy = false

  # activate_apis is the set of base_apis and the APIs required by user-configured deployment options
  activate_apis = concat(local.base_apis, var.memorystore ? local.memorystore_apis : [])
}

# Create GKE cluster
resource "google_container_cluster" "my_cluster" {

  name     = var.name
  location = var.region

  # Enable autopilot for this cluster
  enable_autopilot = true

  # Set an empty ip_allocation_policy to allow autopilot cluster to spin up correctly
  ip_allocation_policy {
  }

  # Avoid setting deletion_protection to false
  # until you're ready (and certain you want) to destroy the cluster.
  # deletion_protection = false

  depends_on = [
    module.enable_google_apis
  ]
}

# Get credentials for cluster
module "gcloud" {
  source  = "terraform-google-modules/gcloud/google"
  version = "~> 4.0"

  platform              = "linux"
  additional_components = ["kubectl", "beta"]

  create_cmd_entrypoint = "gcloud"
  # Module does not support explicit dependency
  # Enforce implicit dependency through use of local variable
  create_cmd_body = "container clusters get-credentials ${local.cluster_name} --zone=${var.region} --project=${var.gcp_project_id}"
}

# Apply YAML kubernetes-manifest configurations
resource "null_resource" "apply_deployment" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = "kubectl apply -k ${var.filepath_manifest} -n ${var.namespace}"
  }

  depends_on = [
    module.gcloud
  ]
}

# Service account for monitoring integrations
resource "google_service_account" "monitoring_sa" {
  count        = var.enable_monitoring_sa ? 1 : 0
  account_id   = "boutique-monitoring"
  display_name = "Online Boutique Monitoring"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "monitoring_sa_roles" {
  for_each = var.enable_monitoring_sa ? toset([
    "roles/monitoring.admin",
    "roles/logging.admin",
    "roles/container.admin",
    "roles/iam.serviceAccountUser",
    "roles/editor",
  ]) : toset([])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.monitoring_sa[0].email}"
}

resource "google_service_account_key" "monitoring_sa_key" {
  count              = var.enable_monitoring_sa ? 1 : 0
  service_account_id = google_service_account.monitoring_sa[0].name
}

# Firewall rule to allow SSH access to GKE nodes for troubleshooting
resource "google_compute_firewall" "allow_ssh_to_gke" {
  name    = "allow-ssh-gke-nodes"
  network = "default"
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["22", "10250", "6443", "8443", "9229"]
  }

  source_ranges = var.allowed_ssh_ranges
  target_tags   = ["gke-${var.name}"]
}

# Wait condition for all Pods to be ready before finishing
resource "null_resource" "wait_conditions" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = <<-EOT
    kubectl wait --for=condition=AVAILABLE apiservice/v1beta1.metrics.k8s.io --timeout=180s
    kubectl wait --for=condition=ready pods --all -n ${var.namespace} --timeout=280s
    EOT
  }

  depends_on = [
    resource.null_resource.apply_deployment
  ]
}
