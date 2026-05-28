terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_serverless_cloud_gateway" "this" {
  cluster_cert     = var.cluster_cert
  cluster_cert_key = var.cluster_cert_key
  labels           = length(var.labels) > 0 ? var.labels : null

  control_plane = {
    id     = var.control_plane_id
    prefix = var.control_plane_prefix
    region = var.control_plane_region
  }
}

output "id" {
  description = "The Serverless Cloud Gateway ID"
  value       = konnect_serverless_cloud_gateway.this.control_plane.id
}

output "gateway_endpoint" {
  description = "The endpoint for the serverless cloud gateway"
  value       = konnect_serverless_cloud_gateway.this.gateway_endpoint
}
